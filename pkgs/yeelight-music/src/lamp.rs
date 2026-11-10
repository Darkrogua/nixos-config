//! Yeelight LAN protocol (TCP 55443). Controls only the RGB background light (`bg_*`).
//!
//! This Screen Light Bar does not support `set_music` ("method not supported").
//! Normal mode is quota-limited (~60 commands/min per TCP connection, max 2
//! connections), so we keep a small pool and drive colour+brightness with
//! `bg_start_cf` (one command, smooth transition). If music mode works on
//! another lamp, we stream `bg_set_scene` without the quota.

use anyhow::{anyhow, Context, Result};
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::time::{Duration, Instant};

const CONNECT_GRACE: Duration = Duration::from_millis(150);
const CMD_TIMEOUT: Duration = Duration::from_secs(8);
const OFF_CMD_TIMEOUT: Duration = Duration::from_secs(2);
const QUOTA_PER_MIN: f64 = 58.0;

pub struct Lamp {
    ip: String,
    port: u16,
    next_id: u32,
    /// Control / quota-mode sockets (up to 2).
    pool: Vec<Pooled>,
    /// Incoming music-mode socket from the lamp, if enabled.
    music: Option<TcpStream>,
    music_enabled: bool,
}

struct Pooled {
    stream: TcpStream,
    quota: Quota,
}

struct Quota {
    tokens: f64,
    cap: f64,
    refill_per_sec: f64,
    last: Instant,
}

impl Quota {
    fn new() -> Self {
        Self {
            tokens: QUOTA_PER_MIN,
            cap: QUOTA_PER_MIN,
            refill_per_sec: QUOTA_PER_MIN / 60.0,
            last: Instant::now(),
        }
    }

    fn refill(&mut self) {
        let now = Instant::now();
        let dt = now.saturating_duration_since(self.last).as_secs_f64();
        self.last = now;
        self.tokens = (self.tokens + dt * self.refill_per_sec).min(self.cap);
    }

    fn try_take(&mut self) -> bool {
        self.refill();
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }

    fn exhausted(&mut self) {
        self.tokens = 0.0;
        self.last = Instant::now();
    }
}

impl Lamp {
    pub fn connect(ip: &str, port: u16) -> Result<Self> {
        let mut lamp = Self {
            ip: ip.to_string(),
            port,
            next_id: 1,
            pool: Vec::new(),
            music: None,
            music_enabled: false,
        };
        let stream = open_stream(ip, port)?;
        lamp.pool.push(Pooled {
            stream,
            quota: Quota::new(),
        });
        Ok(lamp)
    }

    /// Open additional quota connections. This lamp only accepts two
    /// simultaneous LAN clients; a third is dropped.
    pub fn try_expand_pool(&mut self, want: usize) {
        let want = want.clamp(1, 2);
        while self.pool.len() < want {
            match open_stream(&self.ip, self.port) {
                Ok(stream) => {
                    self.pool.push(Pooled {
                        stream,
                        quota: Quota::new(),
                    });
                }
                Err(e) => {
                    eprintln!("yeelight-music: extra LAN connection failed: {e}");
                    break;
                }
            }
        }
        eprintln!(
            "yeelight-music: opened {} LAN connections (quota ~{} cmd/min each)",
            self.pool.len(),
            QUOTA_PER_MIN as u32
        );
    }

    /// Attempt Yeelight music mode. Returns true if the lamp connected back
    /// and we can stream without the 60/min quota.
    pub fn try_music_mode(&mut self, bind: &str, music_port: u16) -> Result<bool> {
        let listener = match TcpListener::bind((bind, music_port)) {
            Ok(l) => l,
            Err(e) => {
                eprintln!(
                    "yeelight-music: cannot bind music listener {bind}:{music_port}: {e}"
                );
                return Ok(false);
            }
        };
        listener
            .set_nonblocking(true)
            .context("music listener nonblocking")?;

        let resp = match self.rpc_first("set_music", json!([1, bind, music_port])) {
            Ok(v) => v,
            Err(e) => {
                eprintln!("yeelight-music: set_music failed: {e}");
                return Ok(false);
            }
        };
        if let Some(err) = resp.get("error") {
            eprintln!("yeelight-music: set_music not available: {err}");
            return Ok(false);
        }

        let deadline = Instant::now() + Duration::from_secs(8);
        while Instant::now() < deadline {
            match listener.accept() {
                Ok((stream, addr)) => {
                    let _ = stream.set_nodelay(true);
                    let _ = stream.set_read_timeout(Some(Duration::from_millis(200)));
                    eprintln!("yeelight-music: music mode on (lamp {addr})");
                    self.music = Some(stream);
                    self.music_enabled = true;
                    return Ok(true);
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(50));
                }
                Err(e) => {
                    eprintln!("yeelight-music: music accept error: {e}");
                    break;
                }
            }
        }
        eprintln!("yeelight-music: lamp did not connect back for music mode");
        let _ = self.rpc_first("set_music", json!([0]));
        Ok(false)
    }

    pub fn ensure_bg_on(&mut self) -> Result<()> {
        self.rpc_first("bg_set_power", json!(["on", "smooth", 300]))?;
        Ok(())
    }

    /// Update the background light. In music mode this is unthrottled; otherwise
    /// it consumes one token from the connection pool and may skip if exhausted.
    pub fn set_bg(&mut self, rgb: u32, bright: u32, duration_ms: u32) -> Result<bool> {
        let rgb = rgb & 0xFFFFFF;
        let bright = bright.clamp(1, 100);
        if self.music.is_some() {
            return self.set_bg_music(rgb, bright, duration_ms);
        }
        self.set_bg_quota(rgb, bright, duration_ms)
    }

    fn set_bg_music(&mut self, rgb: u32, bright: u32, duration_ms: u32) -> Result<bool> {
        let id = self.alloc_id();
        let dur = duration_ms.max(30);
        let payload = json!({
            "id": id,
            "method": "bg_set_scene",
            "params": ["color", rgb, bright],
        });
        // Prefer a single scene command; fall back is unnecessary if write works.
        // Use short smooth via color flow if we want interpolation even at high fps:
        let payload = if dur >= 40 {
            json!({
                "id": id,
                "method": "bg_start_cf",
                "params": [1, 1, format!("{dur},1,{rgb},{bright}")],
            })
        } else {
            payload
        };
        if let Some(stream) = self.music.as_mut() {
            if let Err(e) = write_json(stream, &payload) {
                eprintln!("yeelight-music: music socket write failed: {e}");
                self.music = None;
                return Ok(false);
            }
        }
        Ok(true)
    }

    fn set_bg_quota(&mut self, rgb: u32, bright: u32, duration_ms: u32) -> Result<bool> {
        self.drop_dead_pool();
        if self.pool.is_empty() {
            match open_stream(&self.ip, self.port) {
                Ok(stream) => self.pool.push(Pooled {
                    stream,
                    quota: Quota::new(),
                }),
                Err(e) => return Err(e),
            }
        }

        let idx = self
            .pool
            .iter_mut()
            .enumerate()
            .map(|(i, p)| {
                p.quota.refill();
                (i, p.quota.tokens)
            })
            .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(i, _)| i);

        let Some(idx) = idx else {
            return Ok(false);
        };
        if !self.pool[idx].quota.try_take() {
            return Ok(false);
        }

        let id = self.alloc_id();
        let dur = duration_ms.clamp(200, 800);
        let payload = json!({
            "id": id,
            "method": "bg_start_cf",
            "params": [1, 1, format!("{dur},1,{rgb},{bright}")],
        });

        match rpc_on(&mut self.pool[idx].stream, id, &payload, CMD_TIMEOUT) {
            Ok(resp) => {
                if let Some(err) = resp.get("error") {
                    let msg = err
                        .get("message")
                        .and_then(|m| m.as_str())
                        .unwrap_or("")
                        .to_string();
                    if msg.contains("quota") {
                        self.pool[idx].quota.exhausted();
                        return Ok(false);
                    }
                    eprintln!("yeelight-music: bg_start_cf error: {err}");
                    return Ok(false);
                }
                Ok(true)
            }
            Err(e) => {
                eprintln!("yeelight-music: send failed, dropping connection: {e}");
                self.pool.remove(idx);
                Ok(false)
            }
        }
    }

    /// Turn the RGB backlight off. Never opens a third TCP socket while the
    /// pool still holds the lamp's two slots. Does not touch the main light.
    pub fn turn_bg_off(&mut self) -> Result<()> {
        if self.music_enabled {
            let _ = self.rpc_existing("set_music", json!([0]), OFF_CMD_TIMEOUT);
            self.music_enabled = false;
        }
        if let Some(stream) = self.music.take() {
            let _ = stream.shutdown(Shutdown::Both);
            drop(stream);
        }

        if !self.pool.is_empty() {
            match self.try_power_off_on_pool() {
                Ok(()) => {
                    eprintln!("yeelight-music: bg_power off (existing connection)");
                    self.close_all();
                    return Ok(());
                }
                Err(e) => {
                    eprintln!("yeelight-music: off via existing connection failed: {e}");
                }
            }
        }

        let mut delay_ms = 500u64;
        for attempt in 1..=5 {
            self.close_all();
            std::thread::sleep(Duration::from_millis(delay_ms));
            match self.reconnect_one() {
                Ok(()) => match self.try_power_off_fresh() {
                    Ok(()) => {
                        eprintln!("yeelight-music: bg_power off (attempt {attempt})");
                        self.close_all();
                        return Ok(());
                    }
                    Err(e) => {
                        eprintln!("yeelight-music: bg off attempt {attempt} failed: {e}");
                    }
                },
                Err(e) => {
                    eprintln!("yeelight-music: reconnect for off attempt {attempt} failed: {e}");
                }
            }
            delay_ms = (delay_ms + 300).min(1500);
        }
        Err(anyhow!("failed to turn bg off after retries"))
    }

    fn close_all(&mut self) {
        if let Some(stream) = self.music.take() {
            let _ = stream.shutdown(Shutdown::Both);
            drop(stream);
        }
        self.music_enabled = false;
        for pooled in self.pool.drain(..) {
            let _ = pooled.stream.shutdown(Shutdown::Both);
            drop(pooled);
        }
    }

    fn reconnect_one(&mut self) -> Result<()> {
        if !self.pool.is_empty() || self.music.is_some() {
            self.close_all();
        }
        let stream = open_stream(&self.ip, self.port)?;
        self.pool.push(Pooled {
            stream,
            quota: Quota::new(),
        });
        Ok(())
    }

    fn best_quota_idx(&mut self) -> Option<usize> {
        self.pool
            .iter_mut()
            .enumerate()
            .map(|(i, p)| {
                p.quota.refill();
                (i, p.quota.tokens)
            })
            .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
            .and_then(|(i, tokens)| if tokens >= 1.0 { Some(i) } else { None })
    }

    fn rpc_existing(&mut self, method: &str, params: Value, timeout: Duration) -> Result<Value> {
        let idx = self
            .best_quota_idx()
            .ok_or_else(|| anyhow!("no LAN connection with remaining quota"))?;
        let _ = self.pool[idx].quota.try_take();
        let id = self.alloc_id();
        let payload = json!({"id": id, "method": method, "params": params});
        match rpc_on(&mut self.pool[idx].stream, id, &payload, timeout) {
            Ok(v) => {
                if let Some(err) = v.get("error") {
                    let msg = err
                        .get("message")
                        .and_then(|m| m.as_str())
                        .unwrap_or("");
                    if msg.contains("quota") {
                        self.pool[idx].quota.exhausted();
                    }
                    return Err(anyhow!("{method} error: {err}"));
                }
                Ok(v)
            }
            Err(e) => {
                self.pool.remove(idx);
                Err(e)
            }
        }
    }

    fn bg_is_off(&mut self) -> bool {
        match self.rpc_existing("get_prop", json!(["bg_power"]), OFF_CMD_TIMEOUT) {
            Ok(resp) => {
                resp.get("result")
                    .and_then(|r| r.as_array())
                    .and_then(|a| a.first())
                    .and_then(|v| v.as_str())
                    == Some("off")
            }
            Err(e) => {
                eprintln!("yeelight-music: get_prop bg_power failed: {e}");
                false
            }
        }
    }

    fn try_power_off_on_pool(&mut self) -> Result<()> {
        if self.pool.is_empty() {
            return Err(anyhow!("no existing connections"));
        }
        match self.rpc_existing("bg_stop_cf", json!([]), OFF_CMD_TIMEOUT) {
            Ok(_) => {}
            Err(e) => {
                if self.pool.is_empty() {
                    return Err(e);
                }
                // Method/quota error but the socket is still up — continue.
                eprintln!("yeelight-music: bg_stop_cf: {e}");
            }
        }
        self.rpc_existing(
            "bg_set_power",
            json!(["off", "sudden", 0]),
            OFF_CMD_TIMEOUT,
        )?;
        if self.bg_is_off() {
            Ok(())
        } else {
            Err(anyhow!("bg_power still on after bg_set_power"))
        }
    }

    /// After a full reconnect the colour flow is already gone; only power off + verify.
    fn try_power_off_fresh(&mut self) -> Result<()> {
        if self.pool.is_empty() {
            return Err(anyhow!("reconnect produced no connection"));
        }
        self.rpc_existing(
            "bg_set_power",
            json!(["off", "sudden", 0]),
            OFF_CMD_TIMEOUT,
        )?;
        if self.bg_is_off() {
            Ok(())
        } else {
            Err(anyhow!("bg_power still on after bg_set_power"))
        }
    }

    pub fn pool_len(&self) -> usize {
        self.pool.len()
    }

    fn rpc_first(&mut self, method: &str, params: Value) -> Result<Value> {
        self.drop_dead_pool();
        if self.pool.is_empty() {
            let stream = open_stream(&self.ip, self.port)?;
            self.pool.push(Pooled {
                stream,
                quota: Quota::new(),
            });
        }
        let id = self.alloc_id();
        let payload = json!({"id": id, "method": method, "params": params});
        // get_prop / set_music also count against quota; take a token if possible
        // but do not refuse control commands.
        self.pool[0].quota.try_take();
        match rpc_on(&mut self.pool[0].stream, id, &payload, CMD_TIMEOUT) {
            Ok(v) => Ok(v),
            Err(e) => {
                self.pool.remove(0);
                Err(e)
            }
        }
    }

    fn alloc_id(&mut self) -> u32 {
        let id = self.next_id;
        self.next_id = self.next_id.wrapping_add(1);
        if self.next_id == 0 {
            self.next_id = 1;
        }
        id
    }

    fn drop_dead_pool(&mut self) {
        // failed I/O removes sockets at the call site
    }
}

fn open_stream(ip: &str, port: u16) -> Result<TcpStream> {
    let stream = TcpStream::connect_timeout(
        &format!("{ip}:{port}")
            .parse()
            .context("lamp address")?,
        Duration::from_secs(5),
    )
    .with_context(|| format!("connect {ip}:{port}"))?;
    let _ = stream.set_nodelay(true);
    let _ = stream.set_read_timeout(Some(Duration::from_millis(400)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(3)));
    // The lamp silently drops commands sent immediately after the handshake.
    std::thread::sleep(CONNECT_GRACE);
    Ok(stream)
}

fn write_json(stream: &mut TcpStream, payload: &Value) -> Result<()> {
    let mut line = payload.to_string();
    line.push_str("\r\n");
    let mut buf = line.as_bytes();
    while !buf.is_empty() {
        match stream.write(buf) {
            Ok(0) => {
                return Err(anyhow!("lamp closed the connection during write"));
            }
            Ok(n) => buf = &buf[n..],
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e.into()),
        }
    }
    loop {
        match stream.flush() {
            Ok(()) => return Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e.into()),
        }
    }
}

fn rpc_on(stream: &mut TcpStream, id: u32, payload: &Value, timeout: Duration) -> Result<Value> {
    write_json(stream, payload)?;
    let deadline = Instant::now() + timeout;
    let mut buf = Vec::new();
    let mut tmp = [0u8; 4096];
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Err(anyhow!("timeout waiting for lamp reply id={id}"));
        }
        // The socket's read timeout is 400ms; loop until deadline.
        match stream.read(&mut tmp) {
            Ok(0) => return Err(anyhow!("lamp closed the connection")),
            Ok(n) => {
                buf.extend_from_slice(&tmp[..n]);
                while let Some(pos) = buf.iter().position(|&b| b == b'\n') {
                    let mut line = buf.drain(..=pos).collect::<Vec<_>>();
                    if line.ends_with(&[b'\n']) {
                        line.pop();
                    }
                    if line.ends_with(&[b'\r']) {
                        line.pop();
                    }
                    if line.is_empty() {
                        continue;
                    }
                    let text = String::from_utf8_lossy(&line);
                    let obj: Value = serde_json::from_str(&text)
                        .with_context(|| format!("lamp JSON: {text}"))?;
                    if obj.get("id").and_then(|v| v.as_u64()) == Some(id as u64) {
                        return Ok(obj);
                    }
                    // Unsolicited {"method":"props",...} and other replies are ignored.
                }
            }
            Err(e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut
                    || e.kind() == std::io::ErrorKind::Interrupted =>
            {
                continue;
            }
            Err(e) => return Err(e.into()),
        }
    }
}

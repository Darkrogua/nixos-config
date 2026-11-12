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
const QUOTA_PER_MIN: f64 = 50.0;
/// Tokens kept on each LAN connection so shutdown still has room after a
/// sustained visualizer run (the lamp rejects extra commands with
/// "client quota exceeded"; reconnecting does not reset that window).
const SHUTDOWN_RESERVE: f64 = 4.0;
/// Keep colour-flow duration under the ~650 ms send interval so a new
/// `bg_start_cf` does not start while the previous flow is still running.
/// Overlapping flows can desync the firmware (`bg_flowing` stuck on, `bg_set_power
/// off` becomes a no-op while get_prop already reports off).
const CF_MAX_DURATION_MS: u32 = 540;
/// Forced on→off dance: this lamp may report `bg_power=off` and ack off while
/// the rear RGB stays lit. A confirmed visual off is: power on, wait, power off.
const OFF_FORCE_ON_WAIT: Duration = Duration::from_millis(1200);
const OFF_AFTER_OFF_WAIT: Duration = Duration::from_millis(600);

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

    /// One-shot background colour-flow of up to 9 tuples, then stay at the last frame.
    /// Each tuple is (duration_ms, rgb, brightness); durations are clamped to ≥ 50 ms.
    pub fn start_bg_cf(&mut self, frames: &[(u32, u32, u32)]) -> Result<bool> {
        let Some(expr) = format_cf(frames) else {
            return Ok(false);
        };
        let params = json!([1, 1, expr]);
        if self.music.is_some() {
            return self.send_music("bg_start_cf", params);
        }
        self.send_quota("bg_start_cf", params)
    }

    pub fn stop_bg_cf(&mut self) -> Result<bool> {
        if self.music.is_some() {
            return self.send_music("bg_stop_cf", json!([]));
        }
        self.send_quota("bg_stop_cf", json!([]))
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
        // Leave SHUTDOWN_RESERVE tokens so the on→off dance is not refused
        // after a long session sitting at the lamp's ~60/min cap.
        if self.pool[idx].quota.tokens < 1.0 + SHUTDOWN_RESERVE
            || !self.pool[idx].quota.try_take()
        {
            return Ok(false);
        }

        let id = self.alloc_id();
        let dur = duration_ms.clamp(200, CF_MAX_DURATION_MS);
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
    ///
    /// A plain `bg_set_power off` can be a no-op on this firmware: it acks "ok"
    /// and `get_prop bg_power` returns "off" while the rear RGB stays lit, and
    /// it never emits a `props` notification for `bg_power=off`. The reliable
    /// sequence is: stop any colour flow, force `bg_set_power on`, wait, then
    /// `bg_set_power off` with a short smooth transition.
    pub fn turn_bg_off(&mut self) -> Result<()> {
        if self.music_enabled {
            let _ = self.rpc_shutdown("set_music", json!([0]), OFF_CMD_TIMEOUT);
            self.music_enabled = false;
        }
        if let Some(stream) = self.music.take() {
            let _ = stream.shutdown(Shutdown::Both);
            drop(stream);
        }

        let mut delay = Duration::from_secs(3);
        for attempt in 1..=4 {
            if self.pool.is_empty() {
                if let Err(e) = self.reconnect_one() {
                    eprintln!("yeelight-music: reconnect for off attempt {attempt} failed: {e}");
                    std::thread::sleep(delay);
                    delay = (delay * 2).min(Duration::from_secs(8));
                    continue;
                }
            }
            match self.force_bg_off_sequence() {
                Ok(()) => {
                    if attempt == 1 {
                        eprintln!("yeelight-music: bg_power off (on→off, existing connection)");
                    } else {
                        eprintln!("yeelight-music: bg_power off (on→off, attempt {attempt})");
                    }
                    self.close_all();
                    return Ok(());
                }
                Err(e) => {
                    eprintln!("yeelight-music: off attempt {attempt} failed: {e}");
                    let quota = is_quota_error(&e);
                    if quota {
                        // Lamp-side window is shared; closing sockets does not
                        // refill it. Wait, then retry on the same connection.
                        eprintln!("yeelight-music: lamp quota exceeded, waiting {delay:?}");
                        std::thread::sleep(delay);
                        delay = (delay * 2).min(Duration::from_secs(8));
                    } else {
                        self.close_all();
                        std::thread::sleep(Duration::from_millis(500));
                    }
                }
            }
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

    /// Prefer a connection with remaining quota; if `require_token` is false
    /// (shutdown path), fall back to any live socket so off is never skipped.
    fn best_idx(&mut self, require_token: bool) -> Option<usize> {
        let ranked: Vec<(usize, f64)> = self
            .pool
            .iter_mut()
            .enumerate()
            .map(|(i, p)| {
                p.quota.refill();
                (i, p.quota.tokens)
            })
            .collect();
        ranked
            .iter()
            .cloned()
            .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
            .and_then(|(i, tokens)| {
                if !require_token || tokens >= 1.0 {
                    Some(i)
                } else {
                    None
                }
            })
    }

    fn rpc_shutdown(&mut self, method: &str, params: Value, timeout: Duration) -> Result<Value> {
        self.rpc_on_idx(method, params, timeout, false)
    }

    /// Shutdown commands must get through even when the visualizer just
    /// exhausted the lamp window. Wait for refill instead of giving up.
    fn rpc_shutdown_wait(&mut self, method: &str, params: Value, timeout: Duration) -> Result<Value> {
        let mut delay = Duration::from_secs(3);
        let mut attempt = 0u32;
        loop {
            attempt += 1;
            if self.pool.is_empty() {
                self.reconnect_one()?;
            }
            match self.rpc_shutdown(method, params.clone(), timeout) {
                Ok(v) => return Ok(v),
                Err(e) if is_quota_error(&e) && attempt < 3 => {
                    eprintln!(
                        "yeelight-music: {method} quota exceeded (attempt {attempt}); retry in {delay:?}"
                    );
                    std::thread::sleep(delay);
                    delay = (delay + Duration::from_secs(2)).min(Duration::from_secs(7));
                }
                Err(e) => return Err(e),
            }
        }
    }

    fn rpc_on_idx(
        &mut self,
        method: &str,
        params: Value,
        timeout: Duration,
        require_token: bool,
    ) -> Result<Value> {
        let idx = self
            .best_idx(require_token)
            .ok_or_else(|| anyhow!("no LAN connection available"))?;
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
        match self.rpc_shutdown("get_prop", json!(["bg_power"]), OFF_CMD_TIMEOUT) {
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

    /// Stop flow, force the backlight on, wait, then smooth-off and verify.
    /// Always performs the dance even if get_prop already says "off".
    fn force_bg_off_sequence(&mut self) -> Result<()> {
        if self.pool.is_empty() {
            return Err(anyhow!("no existing connections"));
        }
        match self.rpc_shutdown_wait("bg_stop_cf", json!([]), OFF_CMD_TIMEOUT) {
            Ok(_) => eprintln!("yeelight-music: colour flow stopped"),
            Err(e) => {
                if self.pool.is_empty() {
                    return Err(e);
                }
                eprintln!("yeelight-music: bg_stop_cf: {e}");
            }
        }

        eprintln!("yeelight-music: forcing bg_power on before off");
        self.rpc_shutdown_wait(
            "bg_set_power",
            json!(["on", "smooth", 300]),
            OFF_CMD_TIMEOUT,
        )?;
        std::thread::sleep(OFF_FORCE_ON_WAIT);

        self.rpc_shutdown_wait(
            "bg_set_power",
            json!(["off", "smooth", 500]),
            OFF_CMD_TIMEOUT,
        )?;
        std::thread::sleep(OFF_AFTER_OFF_WAIT);

        if self.bg_is_off() {
            Ok(())
        } else {
            Err(anyhow!("bg_power still on after on→off sequence"))
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

    fn send_music(&mut self, method: &str, params: Value) -> Result<bool> {
        let id = self.alloc_id();
        let payload = json!({"id": id, "method": method, "params": params});
        if let Some(stream) = self.music.as_mut() {
            if let Err(e) = write_json(stream, &payload) {
                eprintln!("yeelight-music: music socket write failed: {e}");
                self.music = None;
                return Ok(false);
            }
        }
        Ok(true)
    }

    fn send_quota(&mut self, method: &str, params: Value) -> Result<bool> {
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
        if self.pool[idx].quota.tokens < 1.0 + SHUTDOWN_RESERVE
            || !self.pool[idx].quota.try_take()
        {
            return Ok(false);
        }

        let id = self.alloc_id();
        let payload = json!({"id": id, "method": method, "params": params});
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
                    eprintln!("yeelight-music: {method} error: {err}");
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
}

fn format_cf(frames: &[(u32, u32, u32)]) -> Option<String> {
    let mut parts: Vec<String> = Vec::new();
    for &(dur, rgb, bright) in frames.iter().take(9) {
        let dur = dur.max(50);
        let rgb = rgb & 0xFFFFFF;
        let bright = bright.clamp(1, 100);
        parts.push(format!("{dur},1,{rgb},{bright}"));
    }
    if parts.is_empty() {
        None
    } else {
        Some(parts.join(","))
    }
}

fn is_quota_error(err: &anyhow::Error) -> bool {
    err.to_string().to_ascii_lowercase().contains("quota")
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

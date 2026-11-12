//! yeelight-music — map system audio to a Yeelight RGB backlight.
//!
//! Only `bg_*` commands are sent. The front white light is left alone.

mod audio;
mod config;
mod lamp;
mod rhythm;

use anyhow::{Context, Result};
use audio::Spectrum;
use clap::Parser;
use config::{AppConfig, BrightnessMode, EffectMode};
use lamp::Lamp;
use rhythm::{Action, RhythmEngine};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

static RELOAD: AtomicBool = AtomicBool::new(false);
static STOP: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_hup(_: libc::c_int) {
    RELOAD.store(true, Ordering::Relaxed);
}

extern "C" fn handle_stop(_: libc::c_int) {
    STOP.store(true, Ordering::Relaxed);
}

fn install_signals() {
    unsafe {
        libc::signal(libc::SIGHUP, handle_hup as *const () as libc::sighandler_t);
        libc::signal(libc::SIGINT, handle_stop as *const () as libc::sighandler_t);
        libc::signal(libc::SIGTERM, handle_stop as *const () as libc::sighandler_t);
    }
}

#[derive(Parser, Debug)]
#[command(
    name = "yeelight-music",
    about = "Подсветка RGB-фона Yeelight под системный звук"
)]
struct Args {
    /// IP-адрес лампы (иначе из config.toml)
    #[arg(long)]
    ip: Option<String>,

    /// Порт LAN-протокола лампы
    #[arg(long)]
    port: Option<u16>,

    /// Локальный TCP-порт для music mode (лампа подключается обратно)
    #[arg(long)]
    music_port: Option<u16>,

    /// Локальный IP, который сообщаем лампе для music mode
    #[arg(long)]
    bind: Option<String>,

    /// Множитель чувствительности яркости
    #[arg(long)]
    sensitivity: Option<f32>,

    /// Плавность переходов (больше — мягче и чуть медленнее)
    #[arg(long)]
    smoothness: Option<f32>,

    /// Сколько LAN-соединений держать (1–2). Два дают ~2 Гц без music mode.
    #[arg(long)]
    connections: Option<usize>,

    /// Яркость: bass — под низкие частоты; off — как раньше (общая громкость)
    #[arg(long, value_name = "bass|off")]
    brightness_mode: Option<String>,

    /// Эффект: classic — как обычно; rhythm — предсказание бита
    #[arg(long, value_name = "classic|rhythm")]
    effect_mode: Option<String>,

    /// На сколько миллисекунд раньше слать цепочку в режиме rhythm (пик на доле)
    #[arg(long)]
    latency_ms: Option<u32>,

    /// Путь к config.toml (по умолчанию ~/.config/yeelight-music/config.toml)
    #[arg(long)]
    config: Option<PathBuf>,

    /// Только выключить RGB-подсветку и выйти (без захвата звука)
    #[arg(long)]
    off: bool,
}

fn apply_cli(mut cfg: AppConfig, args: &Args) -> AppConfig {
    if let Some(v) = &args.ip {
        cfg.ip = v.clone();
    }
    if let Some(v) = args.port {
        cfg.port = v;
    }
    if let Some(v) = args.music_port {
        cfg.music_port = v;
    }
    if let Some(v) = &args.bind {
        cfg.bind = v.clone();
    }
    if let Some(v) = args.sensitivity {
        cfg.sensitivity = v;
    }
    if let Some(v) = args.smoothness {
        cfg.smoothness = v;
    }
    if let Some(v) = args.connections {
        cfg.connections = v;
    }
    if let Some(v) = &args.brightness_mode {
        cfg.brightness_mode = BrightnessMode::parse(v);
    }
    if let Some(v) = &args.effect_mode {
        cfg.effect_mode = EffectMode::parse(v);
    }
    if let Some(v) = args.latency_ms {
        cfg.latency_ms = v;
    }
    cfg.clamp();
    cfg
}

struct Smoother {
    hue: f32,
    sat: f32,
    energy: f32,
    beat: f32,
    prev_bass: f32,
    bass_peak: f32,
    bass_hold: f32,
}

impl Smoother {
    fn new() -> Self {
        Self {
            hue: 30.0,
            sat: 1.0,
            energy: 0.0,
            beat: 0.0,
            prev_bass: 0.0,
            bass_peak: 0.0,
            bass_hold: 0.0,
        }
    }

    fn update(
        &mut self,
        sp: Spectrum,
        sensitivity: f32,
        smoothness: f32,
        brightness_mode: BrightnessMode,
    ) -> (u32, u32) {
        let sm = smoothness.clamp(0.2, 2.5);
        let hue_alpha = (0.28 / sm).clamp(0.08, 0.6);

        // Contrast-enhanced band energies so the dominant range wins the hue.
        let bass = emphasize(sp.bass);
        let mid = emphasize(sp.mid);
        let treble = emphasize(sp.treble);

        let sum = bass + mid + treble + 1e-9;
        // Weighted hue: bass → red (0°), mid → green (120°), treble → blue (240°).
        let vx = (bass / sum) * 1.0
            + (mid / sum) * (-0.5)
            + (treble / sum) * (-0.5);
        let vy = (bass / sum) * 0.0
            + (mid / sum) * 0.866_025_4
            + (treble / sum) * (-0.866_025_4);
        let target_hue = vy.atan2(vx).to_degrees().rem_euclid(360.0);

        self.hue = lerp_hue(self.hue, target_hue, hue_alpha);
        self.sat = ema(self.sat, 0.95, 0.2);

        let bright = match brightness_mode {
            BrightnessMode::Bass => self.brightness_from_bass(sp, sensitivity, smoothness),
            BrightnessMode::Off => self.brightness_from_level(sp, sensitivity, smoothness),
        };
        let rgb = hsv_to_rgb(self.hue, self.sat);
        (rgb, bright)
    }

    /// Previous behaviour: overall loudness plus a little bass-onset punch.
    fn brightness_from_level(&mut self, sp: Spectrum, sensitivity: f32, smoothness: f32) -> u32 {
        let sm = smoothness.clamp(0.2, 2.5);
        let energy_alpha = (0.32 / sm).clamp(0.1, 0.6);
        let bass = emphasize(sp.bass);

        // RMS of a full-scale sine is ~0.7; music is quieter. 12× at
        // sensitivity=1 puts typical listening levels around mid-high brightness
        // without instantly pegging at 100.
        let rms = (sp.rms * 12.0 * sensitivity.max(0.05)).clamp(0.0, 1.2);
        let rms = rms / (1.0 + 0.35 * rms); // soft knee
        self.energy = ema(self.energy, rms, energy_alpha);

        let flux = (bass - self.prev_bass).max(0.0);
        self.prev_bass = bass;
        let onset = if flux > 0.12 { (flux * 1.8).min(1.0) } else { 0.0 };
        self.beat = (self.beat * 0.72 + onset).min(1.0);

        let loud = (self.energy * 0.88 + self.beat * 0.28).clamp(0.0, 1.0);
        // Never turn the backlight off; dim it on silence.
        (4.0 + loud * 96.0).round().clamp(1.0, 100.0) as u32
    }

    /// Brightness follows ~30–150 Hz kick energy, with auto-gain and peak-hold.
    /// Colour+brightness are sent together in one lamp command by the caller.
    fn brightness_from_bass(&mut self, sp: Spectrum, sensitivity: f32, smoothness: f32) -> u32 {
        let sm = smoothness.clamp(0.2, 2.5);
        // Amplitude-like units; raw FFT power has a huge dynamic range.
        let raw = sp.kick.max(0.0).sqrt();

        if raw > self.bass_peak {
            self.bass_peak = if self.bass_peak < 1e-8 {
                raw
            } else {
                ema(self.bass_peak, raw, 0.35)
            };
        } else if self.bass_peak > 1e-8 {
            // ~15–20 s time constant at ~40 ms frames, so quiet tracks still reach full range.
            self.bass_peak = ema(self.bass_peak, raw, 0.003);
        }

        let norm = if self.bass_peak > 1e-8 {
            (raw / self.bass_peak).clamp(0.0, 1.5)
        } else {
            0.0
        };
        // Gate residual noise relative to the recent peak.
        let gated = if self.bass_peak > 1e-8 && raw < 0.06 * self.bass_peak {
            0.0
        } else {
            (norm / (1.0 + 0.25 * norm)).min(1.0)
        };

        if gated > self.bass_hold {
            self.bass_hold = gated;
        } else {
            let silent = sp.rms < 0.008 && gated < 0.02;
            let decay = if silent {
                0.12
            } else {
                (0.08 / sm).clamp(0.03, 0.2)
            };
            self.bass_hold = ema(self.bass_hold, gated, decay);
        }

        const FLOOR: f32 = 8.0;
        // Scroll intensity (sensitivity) sets how much of the 8–100 range kicks can use.
        let t = ((sensitivity - 0.2) / 2.8).clamp(0.0, 1.0);
        let max_b = 55.0 + 45.0 * t;
        let gamma = (1.3 - 0.5 * t).clamp(0.7, 1.3);
        let loud = self.bass_hold.clamp(0.0, 1.0).powf(gamma);
        (FLOOR + loud * (max_b - FLOOR))
            .round()
            .clamp(FLOOR, 100.0) as u32
    }
}

fn emphasize(x: f32) -> f32 {
    // Mild log + power sharpens the dominant band without ignoring quieter ones.
    let v = (1.0 + x.max(0.0) * 30.0).ln();
    v * v
}

fn ema(prev: f32, new: f32, alpha: f32) -> f32 {
    alpha * new + (1.0 - alpha) * prev
}

fn lerp_hue(a: f32, b: f32, t: f32) -> f32 {
    let mut d = (b - a + 540.0) % 360.0 - 180.0;
    if d < -180.0 {
        d += 360.0;
    }
    (a + t * d).rem_euclid(360.0)
}

fn hsv_to_rgb(h: f32, s: f32) -> u32 {
    let s = s.clamp(0.0, 1.0);
    let c = s;
    let h = h.rem_euclid(360.0);
    let x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    let m = 1.0 - c;
    let (r, g, b) = if h < 60.0 {
        (c, x, 0.0)
    } else if h < 120.0 {
        (x, c, 0.0)
    } else if h < 180.0 {
        (0.0, c, x)
    } else if h < 240.0 {
        (0.0, x, c)
    } else if h < 300.0 {
        (x, 0.0, c)
    } else {
        (c, 0.0, x)
    };
    let r = ((r + m) * 255.0).round() as u32;
    let g = ((g + m) * 255.0).round() as u32;
    let b = ((b + m) * 255.0).round() as u32;
    (r << 16) | (g << 8) | b
}

fn transition_ms(music: bool, smoothness: f32) -> u32 {
    let sm = smoothness.clamp(0.2, 2.5);
    if music {
        (50.0 * sm).round().clamp(30.0, 200.0) as u32
    } else {
        (500.0 * sm).round().clamp(200.0, 900.0) as u32
    }
}

fn stopped() -> bool {
    STOP.load(Ordering::Relaxed)
}

fn try_set_bg(
    lamp: &mut Lamp,
    rgb: u32,
    bright: u32,
    duration_ms: u32,
    min_interval: Duration,
    last_sent: &mut Instant,
    last_rgb: &mut u32,
    last_bright: &mut u32,
) {
    let due = last_sent.elapsed() >= min_interval;
    let changed = rgb != *last_rgb || bright != *last_bright;
    if due && (changed || last_sent.elapsed() >= Duration::from_millis(1500)) {
        match lamp.set_bg(rgb, bright, duration_ms) {
            Ok(true) => {
                *last_sent = Instant::now();
                *last_rgb = rgb;
                *last_bright = bright;
            }
            Ok(false) => {}
            Err(e) => {
                eprintln!("yeelight-music: set_bg error: {e}");
                thread::sleep(Duration::from_millis(200));
            }
        }
    }
}

fn send_chain(
    lamp: &mut Lamp,
    rhythm: &mut RhythmEngine,
    frames: Vec<(u32, u32, u32)>,
    restarted: bool,
    last_sent: &mut Instant,
) {
    match lamp.start_bg_cf(&frames) {
        Ok(true) => {
            rhythm.mark_sent(Instant::now(), &frames, restarted);
            *last_sent = Instant::now();
        }
        Ok(false) => {}
        Err(e) => {
            eprintln!("yeelight-music: start_bg_cf error: {e}");
            thread::sleep(Duration::from_millis(200));
        }
    }
}

/// Retry until the lamp/Wi-Fi is reachable, or until SIGTERM/SIGINT.
fn connect_with_retry(ip: &str, port: u16, max_wait: Option<Duration>) -> Result<Lamp> {
    let mut delay = Duration::from_secs(1);
    let mut attempt = 0u32;
    let start = Instant::now();
    loop {
        if stopped() {
            return Err(anyhow::anyhow!("stopped before connecting to the lamp"));
        }
        if let Some(limit) = max_wait {
            if start.elapsed() >= limit {
                return Err(anyhow::anyhow!("timed out connecting to {ip}:{port}"));
            }
        }
        attempt += 1;
        match Lamp::connect(ip, port) {
            Ok(lamp) => {
                if attempt > 1 {
                    eprintln!("yeelight-music: connected to {ip}:{port} on attempt {attempt}");
                }
                return Ok(lamp);
            }
            Err(e) => {
                eprintln!(
                    "yeelight-music: connect {ip}:{port} failed (attempt {attempt}): {e}; retry in {delay:?}"
                );
                let until = Instant::now() + delay;
                while Instant::now() < until {
                    if stopped() {
                        return Err(anyhow::anyhow!("stopped before connecting to the lamp"));
                    }
                    thread::sleep(Duration::from_millis(100));
                }
                delay = (delay * 2).min(Duration::from_secs(10));
            }
        }
    }
}

fn ensure_bg_on_retry(lamp: &mut Lamp) -> Result<()> {
    let mut delay = Duration::from_millis(400);
    let mut attempt = 0u32;
    loop {
        if stopped() {
            return Err(anyhow::anyhow!("stopped before bg_set_power on"));
        }
        attempt += 1;
        match lamp.ensure_bg_on() {
            Ok(()) => return Ok(()),
            Err(e) => {
                eprintln!("yeelight-music: bg_set_power on failed (attempt {attempt}): {e}");
                thread::sleep(delay);
                delay = (delay * 2).min(Duration::from_secs(5));
            }
        }
    }
}

fn main() -> Result<()> {
    let args = Args::parse();
    install_signals();

    let config_path = args.config.clone().unwrap_or_else(config::default_path);
    if !config_path.exists() {
        if let Err(e) = config::save(&config_path, &AppConfig::default()) {
            eprintln!("yeelight-music: cannot write default config: {e}");
        }
    }
    let file_cfg = config::load(&config_path).unwrap_or_default();
    let mut cfg = apply_cli(file_cfg, &args);
    let mut last_mtime = config::mtime(&config_path);
    eprintln!(
        "yeelight-music: config {} (ip={} sensitivity={} smoothness={} brightness_mode={} effect_mode={} latency_ms={})",
        config_path.display(),
        cfg.ip,
        cfg.sensitivity,
        cfg.smoothness,
        cfg.brightness_mode.as_str(),
        cfg.effect_mode.as_str(),
        cfg.latency_ms
    );

    if args.off {
        let mut lamp = connect_with_retry(&cfg.ip, cfg.port, Some(Duration::from_secs(8)))
            .context("connect for --off")?;
        lamp.turn_bg_off().context("bg_set_power off")?;
        eprintln!("yeelight-music: --off done");
        return Ok(());
    }

    let running = Arc::new(AtomicBool::new(true));

    let mut lamp = match connect_with_retry(&cfg.ip, cfg.port, None) {
        Ok(l) => l,
        Err(e) if stopped() => {
            eprintln!("yeelight-music: {e}");
            return Ok(());
        }
        Err(e) => return Err(e),
    };
    if let Err(e) = ensure_bg_on_retry(&mut lamp) {
        eprintln!("yeelight-music: {e}");
        if let Err(off_err) = lamp.turn_bg_off() {
            eprintln!("yeelight-music: bg_set_power off failed: {off_err}");
        }
        return Ok(());
    }
    eprintln!("yeelight-music: background RGB light on");

    let music = lamp
        .try_music_mode(&cfg.bind, cfg.music_port)
        .unwrap_or(false);
    if !music {
        lamp.try_expand_pool(cfg.connections);
        eprintln!(
            "yeelight-music: music mode unavailable; using {} LAN connection(s) with rate limit (~{:.2} Hz sustained)",
            lamp.pool_len(),
            lamp.pool_len() as f32 * 58.0 / 60.0
        );
    } else {
        eprintln!("yeelight-music: streaming via music mode (~25 updates/s)");
    }

    let (tx, rx) = mpsc::channel::<Spectrum>();
    let audio_flag = running.clone();
    let audio_thread = thread::Builder::new()
        .name("audio-capture".into())
        .spawn(move || audio::capture_loop(audio_flag, tx))
        .context("spawn audio thread")?;

    let mut smoother = Smoother::new();
    let mut rhythm = RhythmEngine::new();
    let mut last_sent = Instant::now() - Duration::from_secs(1);
    let mut last_rgb = 0u32;
    let mut last_bright = 0u32;
    let min_interval = if music {
        Duration::from_millis(40) // 25 Hz
    } else {
        // 2 connections × 50/min ≈ 1.67 Hz; 650 ms leaves headroom for the
        // on→off shutdown sequence (lamp quota is ~60/min and is not reset
        // by reconnecting).
        Duration::from_millis(650)
    };

    let mut latest = Spectrum::default();
    let mut last_poll = Instant::now();
    while running.load(Ordering::Relaxed) && !STOP.load(Ordering::Relaxed) {
        // Drain to the newest spectrum sample; wait a little if none yet.
        let mut got = false;
        while let Ok(sp) = rx.try_recv() {
            latest = sp;
            got = true;
        }
        if !got {
            match rx.recv_timeout(Duration::from_millis(40)) {
                Ok(sp) => latest = sp,
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    // capture_loop retries internally; if it still ended, wait and continue
                    // until SIGTERM rather than leaving the process.
                    eprintln!("yeelight-music: audio thread ended; waiting for stop or restart");
                    thread::sleep(Duration::from_millis(500));
                }
            }
        }

        if !running.load(Ordering::Relaxed) || STOP.load(Ordering::Relaxed) {
            break;
        }

        let file_changed = last_poll.elapsed() >= Duration::from_millis(400)
            && config::mtime(&config_path) != last_mtime;
        if file_changed {
            last_poll = Instant::now();
        }
        if RELOAD.swap(false, Ordering::Relaxed) || file_changed {
            last_mtime = config::mtime(&config_path);
            match config::load(&config_path) {
                Ok(loaded) => {
                    let new_cfg = apply_cli(loaded, &args);
                    if (new_cfg.sensitivity - cfg.sensitivity).abs() > f32::EPSILON
                        || (new_cfg.smoothness - cfg.smoothness).abs() > f32::EPSILON
                        || new_cfg.brightness_mode != cfg.brightness_mode
                        || new_cfg.effect_mode != cfg.effect_mode
                        || new_cfg.latency_ms != cfg.latency_ms
                    {
                        eprintln!(
                            "yeelight-music: reloaded sensitivity={} smoothness={} brightness_mode={} effect_mode={} latency_ms={}",
                            new_cfg.sensitivity,
                            new_cfg.smoothness,
                            new_cfg.brightness_mode.as_str(),
                            new_cfg.effect_mode.as_str(),
                            new_cfg.latency_ms
                        );
                    }
                    if new_cfg.effect_mode != cfg.effect_mode {
                        if cfg.effect_mode == EffectMode::Rhythm {
                            let _ = lamp.stop_bg_cf();
                        }
                        rhythm = RhythmEngine::new();
                    }
                    cfg.sensitivity = new_cfg.sensitivity;
                    cfg.smoothness = new_cfg.smoothness;
                    cfg.brightness_mode = new_cfg.brightness_mode;
                    cfg.effect_mode = new_cfg.effect_mode;
                    cfg.latency_ms = new_cfg.latency_ms;
                }
                Err(e) => eprintln!("yeelight-music: config reload failed: {e}"),
            }
        }

        let (rgb, bright) = smoother.update(latest, cfg.sensitivity, cfg.smoothness, cfg.brightness_mode);
        let duration_ms = transition_ms(music, cfg.smoothness);

        if cfg.effect_mode == EffectMode::Rhythm {
            let now = Instant::now();
            rhythm.update(now, &latest);
            let action = rhythm.poll(
                now,
                cfg.sensitivity,
                cfg.smoothness,
                cfg.brightness_mode,
                Duration::from_millis(cfg.latency_ms as u64),
            );
            match action {
                Action::Hold => {}
                Action::Fallback => {
                    try_set_bg(
                        &mut lamp,
                        rgb,
                        bright,
                        duration_ms,
                        min_interval,
                        &mut last_sent,
                        &mut last_rgb,
                        &mut last_bright,
                    );
                }
                Action::StopAndFallback => {
                    match lamp.stop_bg_cf() {
                        Ok(true) => last_sent = Instant::now(),
                        Ok(false) => {}
                        Err(e) => eprintln!("yeelight-music: bg_stop_cf error: {e}"),
                    }
                    try_set_bg(
                        &mut lamp,
                        rgb,
                        bright,
                        duration_ms,
                        min_interval,
                        &mut last_sent,
                        &mut last_rgb,
                        &mut last_bright,
                    );
                }
                Action::StartCf(frames) => {
                    send_chain(&mut lamp, &mut rhythm, frames, false, &mut last_sent);
                }
                Action::RestartCf(frames) => {
                    match lamp.stop_bg_cf() {
                        Ok(_) => {}
                        Err(e) => eprintln!("yeelight-music: bg_stop_cf error: {e}"),
                    }
                    send_chain(&mut lamp, &mut rhythm, frames, true, &mut last_sent);
                }
            }
        } else {
            try_set_bg(
                &mut lamp,
                rgb,
                bright,
                duration_ms,
                min_interval,
                &mut last_sent,
                &mut last_rgb,
                &mut last_bright,
            );
        }
    }

    running.store(false, Ordering::Relaxed);
    eprintln!("yeelight-music: turning background RGB light off");
    if let Err(e) = lamp.turn_bg_off() {
        eprintln!("yeelight-music: bg_set_power off failed: {e}");
    }
    let _ = audio_thread.join();
    Ok(())
}

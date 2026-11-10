//! yeelight-music — map system audio to a Yeelight RGB backlight.
//!
//! Only `bg_*` commands are sent. The front white light is left alone.

mod audio;
mod config;
mod lamp;

use anyhow::{Context, Result};
use audio::Spectrum;
use clap::Parser;
use config::AppConfig;
use lamp::{BgState, Lamp};
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

    /// Путь к config.toml (по умолчанию ~/.config/yeelight-music/config.toml)
    #[arg(long)]
    config: Option<PathBuf>,
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
    cfg.clamp();
    cfg
}

struct Smoother {
    hue: f32,
    sat: f32,
    energy: f32,
    beat: f32,
    prev_bass: f32,
}

impl Smoother {
    fn new() -> Self {
        Self {
            hue: 30.0,
            sat: 1.0,
            energy: 0.0,
            beat: 0.0,
            prev_bass: 0.0,
        }
    }

    fn update(&mut self, sp: Spectrum, sensitivity: f32, smoothness: f32) -> (u32, u32) {
        let sm = smoothness.clamp(0.2, 2.5);
        let hue_alpha = (0.28 / sm).clamp(0.08, 0.6);
        let energy_alpha = (0.32 / sm).clamp(0.1, 0.6);

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
        let bright = (4.0 + loud * 96.0).round().clamp(1.0, 100.0) as u32;
        let rgb = hsv_to_rgb(self.hue, self.sat);
        (rgb, bright)
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
        "yeelight-music: config {} (ip={} sensitivity={} smoothness={})",
        config_path.display(),
        cfg.ip,
        cfg.sensitivity,
        cfg.smoothness
    );

    let running = Arc::new(AtomicBool::new(true));

    let mut lamp = Lamp::connect(&cfg.ip, cfg.port)
        .with_context(|| format!("connect {}:{}", cfg.ip, cfg.port))?;
    let saved: BgState = lamp.get_bg_state().context("read initial bg state")?;
    eprintln!(
        "yeelight-music: saved bg_power={} bg_rgb={} bg_bright={}",
        saved.power, saved.rgb, saved.bright
    );
    if saved.power != "on" {
        lamp.ensure_bg_on().context("bg_set_power on")?;
    }

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
    let mut last_sent = Instant::now() - Duration::from_secs(1);
    let mut last_rgb = saved.rgb;
    let mut last_bright = saved.bright;
    let min_interval = if music {
        Duration::from_millis(40) // 25 Hz
    } else {
        // 2 connections × 58/min ≈ 1.93 Hz; 520 ms leaves a little headroom.
        Duration::from_millis(520)
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
                    eprintln!("yeelight-music: audio thread ended");
                    break;
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
                    {
                        eprintln!(
                            "yeelight-music: reloaded sensitivity={} smoothness={}",
                            new_cfg.sensitivity, new_cfg.smoothness
                        );
                    }
                    cfg.sensitivity = new_cfg.sensitivity;
                    cfg.smoothness = new_cfg.smoothness;
                }
                Err(e) => eprintln!("yeelight-music: config reload failed: {e}"),
            }
        }

        let (rgb, bright) = smoother.update(latest, cfg.sensitivity, cfg.smoothness);
        let duration_ms = transition_ms(music, cfg.smoothness);
        let due = last_sent.elapsed() >= min_interval;
        let changed = rgb != last_rgb || bright != last_bright;
        if due && (changed || last_sent.elapsed() >= Duration::from_millis(1500)) {
            match lamp.set_bg(rgb, bright, duration_ms) {
                Ok(true) => {
                    last_sent = Instant::now();
                    last_rgb = rgb;
                    last_bright = bright;
                }
                Ok(false) => {
                    // Quota or transient skip; retry on the next frame.
                }
                Err(e) => {
                    eprintln!("yeelight-music: set_bg error: {e}");
                    thread::sleep(Duration::from_millis(200));
                }
            }
        }
    }

    running.store(false, Ordering::Relaxed);
    eprintln!(
        "yeelight-music: restoring bg_power={} bg_rgb={} bg_bright={}",
        saved.power, saved.rgb, saved.bright
    );
    if let Err(e) = lamp.restore(&saved) {
        eprintln!("yeelight-music: restore failed: {e}");
    }
    let _ = audio_thread.join();
    Ok(())
}

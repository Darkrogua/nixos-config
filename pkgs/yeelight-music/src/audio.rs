//! Capture the default Pulse/PipeWire sink monitor and produce bass/mid/treble + RMS.

use anyhow::{anyhow, Context, Result};
use libpulse_binding::sample::{Format, Spec};
use libpulse_binding::stream::Direction;
use libpulse_simple_binding::Simple;
use rustfft::num_complex::Complex;
use rustfft::FftPlanner;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::Arc;

pub const SAMPLE_RATE: u32 = 44100;
pub const CHANNELS: u8 = 2;
pub const FFT_SIZE: usize = 2048;

#[derive(Clone, Copy, Debug, Default)]
pub struct Spectrum {
    pub bass: f32,
    pub mid: f32,
    pub treble: f32,
    pub rms: f32,
}

pub fn default_sink_monitor() -> Result<String> {
    use libpulse_binding::context::{Context, FlagSet as ContextFlagSet, State};
    use libpulse_binding::mainloop::standard::{IterateResult, Mainloop};
    use libpulse_binding::proplist::{properties, Proplist};

    let mut ml = Mainloop::new().ok_or_else(|| anyhow!("pulse mainloop"))?;
    let mut proplist = Proplist::new().ok_or_else(|| anyhow!("pulse proplist"))?;
    proplist
        .set_str(properties::APPLICATION_NAME, "yeelight-music")
        .map_err(|_| anyhow!("pulse proplist name"))?;
    let mut ctx = Context::new_with_proplist(&ml, "yeelight-music-ctx", &proplist)
        .ok_or_else(|| anyhow!("pulse context"))?;
    ctx.connect(None, ContextFlagSet::NOFLAGS, None)
        .context("pulse connect")?;

    loop {
        match ml.iterate(false) {
            IterateResult::Quit(_) | IterateResult::Err(_) => {
                return Err(anyhow!("pulse mainloop iterate failed"));
            }
            IterateResult::Success(_) => {}
        }
        match ctx.get_state() {
            State::Ready => break,
            State::Failed | State::Terminated => {
                return Err(anyhow!("pulse context failed"));
            }
            _ => {}
        }
    }

    let (tx, rx) = std::sync::mpsc::channel();
    let introspect = ctx.introspect();
    introspect.get_server_info(move |info| {
        let name = info.default_sink_name.as_ref().map(|s| s.to_string());
        let _ = tx.send(name);
    });

    let mut name = None;
    let start = std::time::Instant::now();
    while name.is_none() && start.elapsed() < std::time::Duration::from_secs(3) {
        let _ = ml.iterate(false);
        if let Ok(v) = rx.try_recv() {
            name = v;
            break;
        }
    }
    ctx.disconnect();
    let name = name.ok_or_else(|| anyhow!("could not read default Pulse sink"))?;
    Ok(format!("{name}.monitor"))
}

pub fn open_capture(monitor: &str) -> Result<Simple> {
    let spec = Spec {
        format: Format::S16le,
        channels: CHANNELS,
        rate: SAMPLE_RATE,
    };
    if !spec.is_valid() {
        return Err(anyhow!("invalid pulse sample spec"));
    }
    Simple::new(
        None,
        "yeelight-music",
        Direction::Record,
        Some(monitor),
        "visualizer",
        &spec,
        None,
        None,
    )
    .with_context(|| format!("pulse record {monitor}"))
}

pub fn capture_loop(running: Arc<AtomicBool>, tx: Sender<Spectrum>) {
    let mut planner = FftPlanner::<f32>::new();
    let fft = planner.plan_fft_forward(FFT_SIZE);
    let window: Vec<f32> = (0..FFT_SIZE)
        .map(|i| {
            0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / (FFT_SIZE as f32 - 1.0)).cos()
        })
        .collect();

    let mut monitor = match default_sink_monitor() {
        Ok(m) => {
            eprintln!("yeelight-music: capturing {m}");
            m
        }
        Err(e) => {
            eprintln!("yeelight-music: cannot resolve default sink monitor: {e}");
            return;
        }
    };
    let mut simple = match open_capture(&monitor) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("yeelight-music: cannot open capture: {e}");
            return;
        }
    };

    // Stereo S16le frames; we mix to mono and hop every FFT_SIZE/2 samples (~23 ms).
    let hop = FFT_SIZE / 2;
    let mut mono: Vec<f32> = Vec::with_capacity(FFT_SIZE * 2);
    let bytes_per_read = hop * CHANNELS as usize * 2;
    let mut raw = vec![0u8; bytes_per_read];
    let mut scratch = vec![Complex::new(0.0, 0.0); FFT_SIZE];
    let mut last_resolve = std::time::Instant::now();

    while running.load(Ordering::Relaxed) {
        if let Err(e) = simple.read(&mut raw) {
            eprintln!("yeelight-music: pulse read failed: {e}; reconnecting");
            std::thread::sleep(std::time::Duration::from_millis(300));
            match default_sink_monitor().and_then(|m| {
                monitor = m.clone();
                open_capture(&m)
            }) {
                Ok(s) => simple = s,
                Err(e) => {
                    eprintln!("yeelight-music: reconnect failed: {e}");
                    std::thread::sleep(std::time::Duration::from_millis(700));
                }
            }
            continue;
        }

        // Periodically follow default sink changes (e.g. headphones unplugged).
        if last_resolve.elapsed() > std::time::Duration::from_secs(4) {
            last_resolve = std::time::Instant::now();
            if let Ok(m) = default_sink_monitor() {
                if m != monitor {
                    eprintln!("yeelight-music: default sink changed, now {m}");
                    if let Ok(s) = open_capture(&m) {
                        simple = s;
                        monitor = m;
                    }
                }
            }
        }

        for frame in raw.chunks_exact((CHANNELS * 2) as usize) {
            let l = i16::from_le_bytes([frame[0], frame[1]]) as f32 / 32768.0;
            let r = i16::from_le_bytes([frame[2], frame[3]]) as f32 / 32768.0;
            mono.push(0.5 * (l + r));
        }
        while mono.len() >= FFT_SIZE {
            let frame = &mono[..FFT_SIZE];
            let mut rms = 0.0f32;
            for (i, &s) in frame.iter().enumerate() {
                rms += s * s;
                scratch[i] = Complex::new(s * window[i], 0.0);
            }
            rms = (rms / FFT_SIZE as f32).sqrt();
            fft.process(&mut scratch);

            let bass = band_energy(&scratch, 30.0, 180.0);
            let mid = band_energy(&scratch, 180.0, 2000.0);
            let treble = band_energy(&scratch, 2000.0, 8000.0);
            if tx.send(Spectrum { bass, mid, treble, rms }).is_err() {
                return;
            }
            mono.drain(..hop);
        }
    }
}

fn band_energy(bins: &[Complex<f32>], lo_hz: f32, hi_hz: f32) -> f32 {
    let n = FFT_SIZE;
    let to_bin = |hz: f32| {
        ((hz * n as f32 / SAMPLE_RATE as f32).round() as usize).clamp(1, n / 2 - 1)
    };
    let a = to_bin(lo_hz);
    let b = to_bin(hi_hz).max(a);
    // Sum of power (not a per-bin average): a sine's energy sits in a few bins,
    // so averaging over a wide mid/treble band would bury it under the noise floor.
    let mut e = 0.0f32;
    for bin in &bins[a..=b] {
        e += bin.norm_sqr();
    }
    e
}

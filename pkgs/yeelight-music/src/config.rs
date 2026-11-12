//! Flat TOML config in ~/.config/yeelight-music/config.toml.

use anyhow::{Context, Result};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

/// How the rear RGB brightness is driven.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrightnessMode {
    /// Colour still follows the music; brightness stays fixed (mapped from sensitivity).
    Off,
    /// Brightness follows low-frequency (kick/bass) energy.
    Bass,
}

impl BrightnessMode {
    pub fn parse(s: &str) -> Self {
        match s.trim().to_ascii_lowercase().as_str() {
            "off" | "fixed" | "false" | "0" | "нет" => Self::Off,
            _ => Self::Bass,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Bass => "bass",
        }
    }

    pub fn label_ru(self) -> &'static str {
        match self {
            Self::Off => "выкл",
            Self::Bass => "под бас",
        }
    }
}

/// Visualiser algorithm. `Classic` is the original colour+bass-brightness loop.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EffectMode {
    Classic,
    /// Beat detection + pre-scheduled colour-flow pulses.
    Rhythm,
}

impl EffectMode {
    pub fn parse(s: &str) -> Self {
        let t = s.trim().to_lowercase();
        // Accept Russian GUI labels too (punctuation is stripped).
        let compact: String = t
            .chars()
            .filter(|c| c.is_alphanumeric())
            .collect();
        if compact.contains("rhythm")
            || compact.contains("beat")
            || compact.contains("ритм")
            || compact.contains("предсказан")
        {
            Self::Rhythm
        } else {
            Self::Classic
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Classic => "classic",
            Self::Rhythm => "rhythm",
        }
    }

    pub fn label_ru(self) -> &'static str {
        match self {
            Self::Classic => "классика",
            Self::Rhythm => "ритм (предсказание бита)",
        }
    }

    pub fn combo_ru(self) -> &'static str {
        match self {
            Self::Classic => "Классика",
            Self::Rhythm => "Ритм (предсказание бита)",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AppConfig {
    pub ip: String,
    pub port: u16,
    pub music_port: u16,
    pub bind: String,
    pub sensitivity: f32,
    pub smoothness: f32,
    pub connections: usize,
    pub brightness_mode: BrightnessMode,
    pub effect_mode: EffectMode,
    /// Send colour-flow chains this early so pulse peaks land on the beat.
    pub latency_ms: u32,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            ip: "192.168.11.50".into(),
            port: 55443,
            music_port: 55444,
            bind: "192.168.11.111".into(),
            sensitivity: 1.0,
            smoothness: 1.0,
            connections: 2,
            brightness_mode: BrightnessMode::Bass,
            effect_mode: EffectMode::Classic,
            latency_ms: 120,
        }
    }
}

impl AppConfig {
    pub fn clamp(&mut self) {
        self.sensitivity = self.sensitivity.clamp(0.2, 3.0);
        self.smoothness = self.smoothness.clamp(0.2, 2.5);
        self.connections = self.connections.clamp(1, 2);
        self.latency_ms = self.latency_ms.clamp(0, 400);
        if self.ip.trim().is_empty() {
            self.ip = Self::default().ip;
        }
    }
}

pub fn default_path() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|h| {
                let mut p = PathBuf::from(h);
                p.push(".config");
                p
            })
        })
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("yeelight-music").join("config.toml")
}

pub fn mtime(path: &Path) -> Option<SystemTime> {
    fs::metadata(path).and_then(|m| m.modified()).ok()
}

pub fn load(path: &Path) -> Result<AppConfig> {
    let mut cfg = AppConfig::default();
    if !path.exists() {
        return Ok(cfg);
    }
    let text = fs::read_to_string(path)
        .with_context(|| format!("read {}", path.display()))?;
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((k, v)) = line.split_once('=') else {
            continue;
        };
        let key = k.trim();
        let mut val = v.trim();
        if (val.starts_with('"') && val.ends_with('"'))
            || (val.starts_with('\'') && val.ends_with('\''))
        {
            val = &val[1..val.len() - 1];
        }
        match key {
            "ip" => cfg.ip = val.to_string(),
            "port" => cfg.port = val.parse().unwrap_or(cfg.port),
            "music_port" => cfg.music_port = val.parse().unwrap_or(cfg.music_port),
            "bind" => cfg.bind = val.to_string(),
            "sensitivity" => cfg.sensitivity = val.parse().unwrap_or(cfg.sensitivity),
            "smoothness" => cfg.smoothness = val.parse().unwrap_or(cfg.smoothness),
            "connections" => cfg.connections = val.parse().unwrap_or(cfg.connections),
            "brightness_mode" => cfg.brightness_mode = BrightnessMode::parse(val),
            "effect_mode" => cfg.effect_mode = EffectMode::parse(val),
            "latency_ms" => cfg.latency_ms = val.parse().unwrap_or(cfg.latency_ms),
            _ => {}
        }
    }
    cfg.clamp();
    Ok(cfg)
}

pub fn save(path: &Path, cfg: &AppConfig) -> Result<()> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).with_context(|| format!("mkdir {}", dir.display()))?;
    }
    let mut c = cfg.clone();
    c.clamp();
    let body = format!(
        "# ~/.config/yeelight-music/config.toml\nip = \"{}\"\nport = {}\nmusic_port = {}\nbind = \"{}\"\nsensitivity = {:.1}\nsmoothness = {:.1}\nconnections = {}\n# brightness_mode: bass — яркость дышит под низкие частоты; off — как раньше (общая громкость)\nbrightness_mode = \"{}\"\n# effect_mode: classic — как обычно; rhythm — предсказание бита и цепочки bg_start_cf\n# В режиме rhythm пульсы яркости работают только если brightness_mode = bass\neffect_mode = \"{}\"\n# latency_ms: на сколько раньше слать цепочку, чтобы пик попал в долю (50–400)\nlatency_ms = {}\n",
        c.ip, c.port, c.music_port, c.bind, c.sensitivity, c.smoothness, c.connections, c.brightness_mode.as_str(), c.effect_mode.as_str(), c.latency_ms
    );
    let tmp = path.with_extension("toml.tmp");
    fs::write(&tmp, body).with_context(|| format!("write {}", tmp.display()))?;
    fs::rename(&tmp, path).with_context(|| format!("replace {}", path.display()))?;
    Ok(())
}

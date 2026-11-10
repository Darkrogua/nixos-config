//! Flat TOML config in ~/.config/yeelight-music/config.toml.

use anyhow::{Context, Result};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, Clone, PartialEq)]
pub struct AppConfig {
    pub ip: String,
    pub port: u16,
    pub music_port: u16,
    pub bind: String,
    pub sensitivity: f32,
    pub smoothness: f32,
    pub connections: usize,
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
        }
    }
}

impl AppConfig {
    pub fn clamp(&mut self) {
        self.sensitivity = self.sensitivity.clamp(0.2, 3.0);
        self.smoothness = self.smoothness.clamp(0.2, 2.5);
        self.connections = self.connections.clamp(1, 2);
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
        "# ~/.config/yeelight-music/config.toml\nip = \"{}\"\nport = {}\nmusic_port = {}\nbind = \"{}\"\nsensitivity = {:.1}\nsmoothness = {:.1}\nconnections = {}\n",
        c.ip, c.port, c.music_port, c.bind, c.sensitivity, c.smoothness, c.connections
    );
    let tmp = path.with_extension("toml.tmp");
    fs::write(&tmp, body).with_context(|| format!("write {}", tmp.display()))?;
    fs::rename(&tmp, path).with_context(|| format!("replace {}", path.display()))?;
    Ok(())
}

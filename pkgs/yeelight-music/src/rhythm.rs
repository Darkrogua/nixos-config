//! Beat-predictive lighting: detect tempo, pre-schedule a short Yeelight colour-flow.
//!
//! One `bg_start_cf` chain covers the next ~2 s (≤ 9 frames, min 50 ms) so we stay
//! near ≤ 1 command/s on a quota-limited lamp. Colour changes on a phrase (every
//! 4–8 beats) or a section jump; brightness pulses on predicted beats.

use crate::audio::Spectrum;
use crate::config::BrightnessMode;
use std::collections::VecDeque;
use std::time::{Duration, Instant};

pub const MIN_FRAME_MS: u32 = 50;
pub const MAX_FRAMES: usize = 9;
pub const CHAIN_TARGET_MS: u32 = 2000;
const MIN_IOI: Duration = Duration::from_millis(200);
const FLUX_WINDOW: usize = 80;
const THRESH_MUL: f32 = 1.5;
const BPM_MIN: f32 = 60.0;
const BPM_MAX: f32 = 200.0;
const BRIGHT_FLOOR: f32 = 8.0;

const WARM: [u32; 4] = [0xFF2A00, 0xFF6A00, 0xFF0038, 0xFFAA00];
const COOL: [u32; 4] = [0x00A0FF, 0x0048FF, 0x7A00FF, 0x00E0C0];

#[derive(Debug, Clone)]
pub enum Action {
    /// No lamp I/O this tick (chain still running).
    Hold,
    /// Use the classic set_bg path (no stable tempo, or mid-breath fallback).
    Fallback,
    /// Stop a leftover flow, then fall back to set_bg.
    StopAndFallback,
    /// Replace the running flow immediately, then start this chain.
    RestartCf(Vec<(u32, u32, u32)>),
    /// Start (or refresh just before the current chain ends) this flow.
    StartCf(Vec<(u32, u32, u32)>),
}

pub struct RhythmEngine {
    fluxes: VecDeque<f32>,
    iois: VecDeque<Duration>,
    last_onset: Option<Instant>,
    period: Option<Duration>,
    bpm: Option<f32>,
    t0: Option<Instant>,
    stable: bool,
    resync: bool,
    chain_until: Option<Instant>,
    last_bpm_log: Option<f32>,
    // AGC
    bass_peak: f32,
    bass_hold: f32,
    // Phrase / section
    rgb: u32,
    family: usize,
    color_idx: usize,
    beats_in_phrase: u32,
    phrase_len: u32,
    last_phrase_at: Option<Instant>,
    timbre_slow: f32,
    energy_slow: f32,
    force_phrase: bool,
    // predicted beat counter for phrase boundaries
    last_beat_k: Option<i64>,
}

impl Default for RhythmEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl RhythmEngine {
    pub fn new() -> Self {
        Self {
            fluxes: VecDeque::with_capacity(FLUX_WINDOW + 1),
            iois: VecDeque::with_capacity(16),
            last_onset: None,
            period: None,
            bpm: None,
            t0: None,
            stable: false,
            resync: false,
            chain_until: None,
            last_bpm_log: None,
            bass_peak: 0.0,
            bass_hold: 0.0,
            rgb: WARM[0],
            family: 0,
            color_idx: 0,
            beats_in_phrase: 0,
            phrase_len: 8,
            last_phrase_at: None,
            timbre_slow: 0.0,
            energy_slow: 0.0,
            force_phrase: false,
            last_beat_k: None,
        }
    }

    pub fn bpm(&self) -> Option<f32> {
        self.bpm
    }

    pub fn stable(&self) -> bool {
        self.stable
    }

    pub fn update(&mut self, now: Instant, sp: &Spectrum) {
        self.note_flux(now, sp.flux);
        self.note_section(now, sp);
        self.advance_phrase(now);
    }

    pub fn poll(
        &mut self,
        now: Instant,
        sensitivity: f32,
        smoothness: f32,
        brightness_mode: BrightnessMode,
        latency: Duration,
    ) -> Action {
        self.update_stability(now);
        if !self.stable {
            if self.chain_until.is_some() {
                self.chain_until = None;
                return Action::StopAndFallback;
            }
            return Action::Fallback;
        }

        let remaining = self.chain_until.map(|until| {
            if now < until {
                until.duration_since(now)
            } else {
                Duration::ZERO
            }
        });
        let due = remaining
            .map(|r| r <= Duration::from_millis(220))
            .unwrap_or(true);
        let restart = self.resync || self.force_phrase;
        if !due && !restart {
            return Action::Hold;
        }

        let Some(t0) = self.t0 else {
            return Action::Fallback;
        };
        let Some(period) = self.period else {
            return Action::Fallback;
        };

        let (peak, floor) = self.levels(sensitivity, brightness_mode);
        if self.force_phrase {
            self.rotate_color(now);
            self.force_phrase = false;
        }

        let attack_s = (0.050 + 0.025 * (smoothness.clamp(0.2, 2.5) - 0.2) / 2.3).clamp(0.050, 0.090);
        let now_s = signed_secs(now, t0);
        let frames = build_chain(
            now_s,
            0.0,
            period.as_secs_f32(),
            latency.as_secs_f32(),
            attack_s,
            self.rgb,
            peak,
            floor,
            MAX_FRAMES,
            CHAIN_TARGET_MS as f32 / 1000.0,
            MIN_FRAME_MS as f32 / 1000.0,
        );
        if frames.is_empty() {
            return Action::Fallback;
        }

        if restart && self.chain_until.is_some() && remaining.unwrap_or(Duration::ZERO) > Duration::from_millis(80)
        {
            Action::RestartCf(frames)
        } else {
            Action::StartCf(frames)
        }
    }

    pub fn mark_sent(&mut self, now: Instant, frames: &[(u32, u32, u32)], restarted: bool) {
        let total: u32 = frames.iter().map(|f| f.0).sum();
        self.chain_until = Some(now + Duration::from_millis(total as u64));
        self.resync = false;
        if let Some(bpm) = self.bpm {
            if self.last_bpm_log.map(|p| (p - bpm).abs() > 1.5).unwrap_or(true) || restarted {
                eprintln!(
                    "yeelight-music: rhythm BPM {:.0} — {} frames / {} ms rgb={:06x}{}",
                    bpm,
                    frames.len(),
                    total,
                    self.rgb,
                    if restarted { " (resync)" } else { "" }
                );
                self.last_bpm_log = Some(bpm);
            }
        }
    }

    fn levels(&mut self, sensitivity: f32, brightness_mode: BrightnessMode) -> (u32, u32) {
        let t = ((sensitivity - 0.2) / 2.8).clamp(0.0, 1.0);
        let max_b = 55.0 + 45.0 * t;
        if brightness_mode == BrightnessMode::Off {
            // No beat pulses: steady level from the intensity wheel. Colour still phrases.
            let steady = (40.0 + t * 50.0).round().clamp(40.0, 100.0) as u32;
            return (steady, steady);
        }
        let loud = self.bass_hold.clamp(0.0, 1.0);
        let peak = (BRIGHT_FLOOR + loud * (max_b - BRIGHT_FLOOR))
            .round()
            .clamp(BRIGHT_FLOOR, 100.0) as u32;
        (peak, BRIGHT_FLOOR.round() as u32)
    }

    fn note_flux(&mut self, now: Instant, flux: f32) {
        self.fluxes.push_back(flux.max(0.0));
        while self.fluxes.len() > FLUX_WINDOW {
            self.fluxes.pop_front();
        }
        if self.fluxes.len() < 16 {
            return;
        }
        let thresh = median_f32(self.fluxes.iter().copied()) * THRESH_MUL;
        let gap_ok = self
            .last_onset
            .map(|t| now.saturating_duration_since(t) >= MIN_IOI)
            .unwrap_or(true);
        if flux > thresh && flux > 1e-5 && gap_ok {
            if let Some(prev) = self.last_onset {
                let ioi = now.saturating_duration_since(prev);
                if ioi <= Duration::from_millis(2000) {
                    self.iois.push_back(ioi);
                    while self.iois.len() > 12 {
                        self.iois.pop_front();
                    }
                }
            }
            self.last_onset = Some(now);
            self.recompute_tempo(now);
        }
    }

    fn note_section(&mut self, now: Instant, sp: &Spectrum) {
        let raw = sp.kick.max(0.0).sqrt();
        if raw > self.bass_peak {
            self.bass_peak = if self.bass_peak < 1e-8 {
                raw
            } else {
                ema(self.bass_peak, raw, 0.35)
            };
        } else if self.bass_peak > 1e-8 {
            self.bass_peak = ema(self.bass_peak, raw, 0.003);
        }
        let norm = if self.bass_peak > 1e-8 {
            (raw / self.bass_peak).clamp(0.0, 1.5)
        } else {
            0.0
        };
        let gated = if self.bass_peak > 1e-8 && raw < 0.06 * self.bass_peak {
            0.0
        } else {
            (norm / (1.0 + 0.25 * norm)).min(1.0)
        };
        if gated > self.bass_hold {
            self.bass_hold = gated;
        } else {
            self.bass_hold = ema(self.bass_hold, gated, 0.06);
        }

        let timbre = (sp.mid + 1e-6) / (sp.bass + sp.mid + sp.treble + 1e-6);
        let prev_t = self.timbre_slow;
        let prev_e = self.energy_slow;
        if prev_t == 0.0 && prev_e == 0.0 {
            self.timbre_slow = timbre;
            self.energy_slow = sp.rms;
            return;
        }
        self.timbre_slow = ema(self.timbre_slow, timbre, 0.08);
        self.energy_slow = ema(self.energy_slow, sp.rms, 0.08);
        let jump = (timbre - prev_t).abs() > 0.20
            || ((sp.rms - prev_e).abs() > 0.10 && sp.rms > prev_e && sp.rms > 0.02);
        let cooled = self
            .last_phrase_at
            .map(|t| now.saturating_duration_since(t) >= Duration::from_millis(1200))
            .unwrap_or(true);
        if jump && cooled {
            self.force_phrase = true;
            self.phrase_len = 4;
        }
    }

    fn advance_phrase(&mut self, now: Instant) {
        let (Some(t0), Some(period)) = (self.t0, self.period) else {
            return;
        };
        let k = (signed_secs(now, t0) / period.as_secs_f32()).floor() as i64;
        if let Some(prev) = self.last_beat_k {
            if k > prev {
                self.beats_in_phrase = self.beats_in_phrase.saturating_add((k - prev) as u32);
                if self.beats_in_phrase >= self.phrase_len {
                    self.force_phrase = true;
                }
            }
        }
        self.last_beat_k = Some(k);
    }

    fn rotate_color(&mut self, now: Instant) {
        self.family = 1 - self.family;
        self.color_idx = (self.color_idx + 1) % 4;
        let pal = if self.family == 0 { &WARM } else { &COOL };
        self.rgb = pal[self.color_idx];
        self.beats_in_phrase = 0;
        self.phrase_len = if self.phrase_len == 4 { 8 } else { 4 + (self.color_idx as u32 % 5) };
        // 4..=8
        self.phrase_len = self.phrase_len.clamp(4, 8);
        self.last_phrase_at = Some(now);
    }

    fn recompute_tempo(&mut self, now: Instant) {
        let Some((bpm, period)) = tempo_from_iois(&self.iois, self.bpm) else {
            return;
        };
        let period_changed = self.period.map(|p| {
            let a = p.as_secs_f32();
            let b = period.as_secs_f32();
            (a - b).abs() / a.max(1e-3) > 0.08
        }).unwrap_or(true);

        if let (Some(t0), Some(onset)) = (self.t0, self.last_onset) {
            let p = period.as_secs_f32();
            let dt = signed_secs(onset, t0);
            let k = (dt / p).round();
            let err = dt - k * p;
            if err.abs() < 0.15 * p {
                self.t0 = Some(shift_instant(t0, err * 0.3));
            } else if period_changed || err.abs() > 0.30 * p {
                self.t0 = Some(onset);
                self.resync = true;
            }
        } else {
            self.t0 = self.last_onset;
            self.resync = true;
        }

        self.period = Some(period);
        if self.bpm.map(|b| (b - bpm).abs() > 2.0).unwrap_or(true) {
            eprintln!(
                "yeelight-music: rhythm tempo {} {:.0} BPM (period {:.0} ms)",
                if self.bpm.is_some() { "→" } else { "locked" },
                bpm,
                period.as_secs_f32() * 1000.0
            );
        }
        self.bpm = Some(bpm);
        let _ = now;
    }

    fn update_stability(&mut self, now: Instant) {
        let was = self.stable;
        let Some(period) = self.period else {
            self.stable = false;
            return;
        };
        let Some(last) = self.last_onset else {
            self.stable = false;
            return;
        };
        let stale_after = (period * 3).max(Duration::from_millis(2500));
        let stale = now.saturating_duration_since(last) > stale_after;
        let consistent = if self.iois.len() >= 4 {
            let vs: Vec<f32> = self.iois.iter().map(|d| d.as_secs_f32()).collect();
            let mean = vs.iter().sum::<f32>() / vs.len() as f32;
            let var = vs.iter().map(|v| (v - mean) * (v - mean)).sum::<f32>() / vs.len() as f32;
            var.sqrt() / mean.max(1e-3) < 0.18
        } else {
            false
        };
        self.stable = !stale && consistent && self.t0.is_some() && self.iois.len() >= 4;
        if self.stable != was {
            if self.stable {
                eprintln!(
                    "yeelight-music: rhythm locked at {:.0} BPM",
                    self.bpm.unwrap_or(0.0)
                );
            } else {
                eprintln!("yeelight-music: rhythm unlocked, falling back to bass envelope");
            }
        }
        if stale && now.saturating_duration_since(last) > Duration::from_secs(6) {
            self.period = None;
            self.bpm = None;
            self.t0 = None;
            self.iois.clear();
            self.last_bpm_log = None;
        }
    }
}

pub(crate) fn tempo_from_iois(
    iois: &VecDeque<Duration>,
    prev_bpm: Option<f32>,
) -> Option<(f32, Duration)> {
    if iois.len() < 4 {
        return None;
    }
    let mut ms: Vec<f32> = iois.iter().map(|d| d.as_secs_f32() * 1000.0).collect();
    ms.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let med = ms[ms.len() / 2];
    if med < 1.0 {
        return None;
    }
    let mut bpm = 60_000.0 / med;
    while bpm < BPM_MIN && bpm * 2.0 <= BPM_MAX * 1.01 {
        bpm *= 2.0;
    }
    while bpm > BPM_MAX && bpm / 2.0 >= BPM_MIN {
        bpm /= 2.0;
    }
    if let Some(prev) = prev_bpm {
        let cands = [bpm, bpm * 2.0, bpm / 2.0];
        bpm = cands
            .iter()
            .copied()
            .filter(|b| *b >= BPM_MIN * 0.95 && *b <= BPM_MAX * 1.05)
            .min_by(|a, b| {
                (a - prev)
                    .abs()
                    .partial_cmp(&(b - prev).abs())
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .unwrap_or(bpm)
            .clamp(BPM_MIN, BPM_MAX);
    } else if !(BPM_MIN..=BPM_MAX).contains(&bpm) {
        return None;
    }
    Some((bpm, Duration::from_secs_f32(60.0 / bpm)))
}

/// Build a colour-flow covering ~`target_s` of predicted beats.
/// `now_s` and `t0_s` are on the same axis (usually t0_s = 0, now_s relative to t0).
pub fn build_chain(
    now_s: f32,
    t0_s: f32,
    period_s: f32,
    latency_s: f32,
    attack_s: f32,
    rgb: u32,
    peak: u32,
    floor: u32,
    max_frames: usize,
    target_s: f32,
    min_frame_s: f32,
) -> Vec<(u32, u32, u32)> {
    if period_s < 0.20 || max_frames == 0 || target_s <= 0.0 {
        return Vec::new();
    }
    let attack_s = attack_s.max(min_frame_s).min((period_s * 0.35).max(min_frame_s));
    let origin = now_s + latency_s;
    let end = origin + target_s;
    let mut pos = origin;
    let mut frames: Vec<(u32, u32, u32)> = Vec::new();
    // First beat at or before origin, then walk forward.
    let mut k = ((origin - t0_s) / period_s).floor();
    if !k.is_finite() {
        return Vec::new();
    }
    // Guard against walking forever if rounding stalls pos.
    for _ in 0..(max_frames * 4 + 8) {
        if frames.len() >= max_frames || pos >= end - 1e-4 {
            break;
        }
        let beat = t0_s + k * period_s;
        let attack_start = beat;
        let attack_end = beat + attack_s;
        let period_end = beat + period_s;

        if period_end <= pos + 1e-4 {
            k += 1.0;
            continue;
        }

        let remain = end - pos;
        if remain < min_frame_s {
            break;
        }

        if pos + 1e-4 < attack_start {
            let gap = attack_start - pos;
            if gap < min_frame_s {
                pos = attack_start;
                continue;
            }
            let dur = gap.min(remain);
            push_frame(&mut frames, dur, rgb, floor, min_frame_s);
            pos += frames.last().map(|f| f.0 as f32 / 1000.0).unwrap_or(dur);
            continue;
        }

        if pos + 1e-4 < attack_end {
            let gap = attack_end - pos;
            if gap < min_frame_s {
                pos = attack_end;
                continue;
            }
            let dur = gap.min(remain);
            push_frame(&mut frames, dur, rgb, peak, min_frame_s);
            pos += frames.last().map(|f| f.0 as f32 / 1000.0).unwrap_or(dur);
            continue;
        }

        let gap = period_end - pos;
        if gap < min_frame_s {
            k += 1.0;
            pos = period_end;
            continue;
        }
        let dur = gap.min(remain);
        push_frame(&mut frames, dur, rgb, floor, min_frame_s);
        pos += frames.last().map(|f| f.0 as f32 / 1000.0).unwrap_or(dur);
        k += 1.0;
    }
    frames
}

fn push_frame(frames: &mut Vec<(u32, u32, u32)>, dur_s: f32, rgb: u32, bright: u32, min_s: f32) {
    let min_ms = (min_s * 1000.0).round().max(1.0) as u32;
    let ms = (dur_s * 1000.0).round() as u32;
    let ms = ms.max(min_ms);
    frames.push((ms, rgb & 0xFFFFFF, bright.clamp(1, 100)));
}

fn median_f32(vals: impl IntoIterator<Item = f32>) -> f32 {
    let mut v: Vec<f32> = vals.into_iter().collect();
    if v.is_empty() {
        return 0.0;
    }
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    v[v.len() / 2]
}

fn ema(prev: f32, new: f32, alpha: f32) -> f32 {
    alpha * new + (1.0 - alpha) * prev
}

fn signed_secs(a: Instant, b: Instant) -> f32 {
    if a >= b {
        a.duration_since(b).as_secs_f32()
    } else {
        -b.duration_since(a).as_secs_f32()
    }
}

fn shift_instant(t: Instant, secs: f32) -> Instant {
    if secs >= 0.0 {
        t + Duration::from_secs_f32(secs)
    } else {
        t.checked_sub(Duration::from_secs_f32(-secs)).unwrap_or(t)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bpm_median_and_half_double() {
        let iois: VecDeque<Duration> = [500, 510, 490, 505, 495]
            .into_iter()
            .map(Duration::from_millis)
            .collect();
        let (bpm, period) = tempo_from_iois(&iois, None).unwrap();
        assert!((bpm - 120.0).abs() < 4.0, "bpm={bpm}");
        assert!((period.as_secs_f32() - 0.5).abs() < 0.03);

        // Detected half-time (~60 IOI of 1000 ms → 60 BPM stays; 2000 ms → 30 doubled to 60)
        let slow: VecDeque<Duration> = [2000, 1980, 2010, 1990]
            .into_iter()
            .map(Duration::from_millis)
            .collect();
        let (bpm, _) = tempo_from_iois(&slow, None).unwrap();
        assert!((bpm - 60.0).abs() < 3.0, "half-time bpm={bpm}");

        // Prefer staying near previous when a double-time candidate appears
        let fast: VecDeque<Duration> = [250, 248, 252, 251]
            .into_iter()
            .map(Duration::from_millis)
            .collect();
        let (bpm, _) = tempo_from_iois(&fast, Some(120.0)).unwrap();
        assert!((bpm - 120.0).abs() < 6.0, "prefer prev 120, got {bpm}");
    }

    #[test]
    fn chain_respects_frame_and_duration_caps() {
        // 120 BPM, mid-phase start just after a beat
        let frames = build_chain(0.05, 0.0, 0.5, 0.12, 0.07, 0xFF0000, 90, 8, 9, 2.0, 0.05);
        assert!(!frames.is_empty());
        assert!(frames.len() <= 9, "frames={}", frames.len());
        let total: u32 = frames.iter().map(|f| f.0).sum();
        assert!(total >= 400, "too short: {total}");
        assert!(total <= 2200, "too long: {total}");
        assert!(frames.iter().all(|f| f.0 >= 50));
        // At least one peak and one floor
        assert!(frames.iter().any(|f| f.2 >= 80));
        assert!(frames.iter().any(|f| f.2 <= 10));
    }

    #[test]
    fn chain_at_high_bpm_stays_within_nine_frames() {
        // 200 BPM = 300 ms period; 2 s would overflow 9 frames if uncapped
        let frames = build_chain(0.0, 0.0, 0.3, 0.12, 0.05, 0x00A0FF, 100, 8, 9, 2.0, 0.05);
        assert!(frames.len() <= 9);
        assert!(frames.iter().all(|f| f.0 >= 50));
        let total: u32 = frames.iter().map(|f| f.0).sum();
        // 4 beats * 300 ms ≈ 1.2 s plus latency alignment
        assert!(total >= 700 && total <= 2200, "total={total}");
    }

    #[test]
    fn chain_durations_sum_to_beat_grid() {
        // Start exactly on a beat, no latency: attack+decay should equal the period.
        let frames = build_chain(0.0, 0.0, 0.5, 0.0, 0.08, 0xFFFFFF, 80, 8, 2, 0.5, 0.05);
        assert_eq!(frames.len(), 2);
        assert_eq!(frames[0].2, 80);
        assert_eq!(frames[1].2, 8);
        assert_eq!(frames[0].0 + frames[1].0, 500);
    }
}

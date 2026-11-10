#!/usr/bin/env bash
# Подготовка к suspend и восстановление после него для Hyprland.
# После s2idle AMD часто пересоздаёт wl_output (HDMI): старый hyprlock +
# мгновенный `dpms on` дают protocol error (invalid object) и рвут всех клиентов.
set -euo pipefail

wait_hyprlock() {
  local i
  for i in $(seq 1 25); do
    if pidof hyprlock >/dev/null 2>&1; then
      sleep 0.4
      return 0
    fi
    sleep 0.2
  done
  return 1
}

wait_monitors() {
  local i
  for i in $(seq 1 40); do
    if hyprctl monitors 2>/dev/null | grep -q '^Monitor '; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

prepare() {
  loginctl lock-session
  wait_hyprlock || true
}

resume() {
  wait_monitors || true
  # HDMI после s2idle часто один раз пропадает и появляется снова
  sleep 1
  wait_monitors || true

  pkill -x hyprlock >/dev/null 2>&1 || true
  sleep 0.3

  hyprctl dispatch 'hl.dsp.dpms({ action = "on" })' >/dev/null 2>&1 || true
  sleep 0.2

  loginctl lock-session
}

case "${1:-}" in
  prepare) prepare ;;
  resume) resume ;;
  *)
    echo "usage: hypr-sleep prepare|resume" >&2
    exit 1
    ;;
esac

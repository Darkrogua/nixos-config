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

# Подсветка Yeelight: гасим RGB до сна, пока Wi-Fi ещё жив (на PrepareForSleep
# NetworkManager сразу рвёт Wi-Fi, поэтому системный хук был бы уже поздно).
# Остановка службы = штатное выключение фона (on→off). После сна включаем
# обратно, только если она работала до этого.
YEELIGHT_MARK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/yeelight-music.paused-for-sleep"

yeelight_off() {
  if systemctl --user is-active --quiet yeelight-music.service; then
    touch "$YEELIGHT_MARK"
    timeout 10 systemctl --user stop yeelight-music.service || true
  fi
}

yeelight_on() {
  if [ -e "$YEELIGHT_MARK" ]; then
    rm -f "$YEELIGHT_MARK"
    systemctl --user start --no-block yeelight-music.service || true
  fi
}

prepare() {
  yeelight_off
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
  yeelight_on
}

case "${1:-}" in
  prepare) prepare ;;
  resume) resume ;;
  *)
    echo "usage: hypr-sleep prepare|resume" >&2
    exit 1
    ;;
esac

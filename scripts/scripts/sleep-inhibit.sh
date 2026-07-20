#!/usr/bin/env bash
# Переключатель блокировки сна для waybar.
# Использование:
#   sleep-inhibit          — статус (JSON для waybar)
#   sleep-inhibit toggle   — вкл/выкл

set -euo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sleep-inhibit.pid"
ICON_AWAKE="󰒳"
ICON_SLEEP="󰒲"
COLOR_AWAKE="#FABD2F"
COLOR_SLEEP="#FBF1C7"

is_active() {
  [[ -f "$STATE_FILE" ]] || return 1
  local pid
  pid="$(cat "$STATE_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

start_inhibit() {
  systemd-inhibit \
    --what=sleep:idle:handle-lid-switch:shutdown \
    --who=sleep-inhibit \
    --why="Сон отключён пользователем (waybar)" \
    --mode=block \
    sleep infinity &
  echo $! >"$STATE_FILE"
}

stop_inhibit() {
  local pid
  pid="$(cat "$STATE_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  rm -f "$STATE_FILE"
}

print_status() {
  if is_active; then
    printf '{"text":"<span foreground='"'"'%s'"'"'>%s </span>","tooltip":"Сон отключён — компьютер не заснёт\\nКлик: разрешить сон","class":"active"}\n' \
      "$COLOR_AWAKE" "$ICON_AWAKE"
  else
    rm -f "$STATE_FILE"
    printf '{"text":"<span foreground='"'"'%s'"'"'>%s </span>","tooltip":"Сон включён\\nКлик: не давать засыпать","class":"inactive"}\n' \
      "$COLOR_SLEEP" "$ICON_SLEEP"
  fi
}

case "${1:-status}" in
  toggle)
    if is_active; then
      stop_inhibit
    else
      start_inhibit
    fi
    print_status
    ;;
  status | "")
    print_status
    ;;
  *)
    echo "usage: sleep-inhibit [toggle|status]" >&2
    exit 1
    ;;
esac

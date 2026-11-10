#!/usr/bin/env bash
# Управление yeelight-music из waybar.
#   yeelight-music-toggle            — статус (JSON для waybar)
#   yeelight-music-toggle toggle     — вкл/выкл сервис (ЛКМ)
#   yeelight-music-toggle settings   — окно настроек (ПКМ)
#   yeelight-music-toggle up|down    — чувствительность (колёсико)
#
# После действий шлём waybar signal 10 (RTMIN+10), чтобы иконка обновилась сразу.

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yeelight-music"
CONFIG="$CONFIG_DIR/config.toml"
WAYBAR_SIGNAL=10

SENS_MIN=0.2
SENS_MAX=3.0
SENS_STEP=0.2

# 7 ступеней яркости (Nerd Font / Maple Mono, md-brightness-1..7)
ICONS=(󰃞 󰃝 󰃟 󰃠 󰃡 󰃢 󰃣)
COLOR_ON="#FABD2F"
COLOR_OFF="#928374"

is_active() {
  systemctl --user is-active --quiet yeelight-music
}

toml_get() {
  local key="$1" default="$2"
  if [[ ! -f "$CONFIG" ]]; then
    printf '%s\n' "$default"
    return
  fi
  awk -F= -v k="$key" -v d="$default" '
    {
      key=$1
      sub(/^[ \t]+/, "", key)
      sub(/[ \t]+$/, "", key)
      if (key == k) {
        val = substr($0, index($0, "=") + 1)
        sub(/^[ \t]+/, "", val)
        sub(/[ \t]+$/, "", val)
        gsub(/^["'\'']|["'\'']$/, "", val)
        print val
        found = 1
        exit
      }
    }
    END { if (!found) print d }
  ' "$CONFIG"
}

ensure_config() {
  mkdir -p "$CONFIG_DIR"
  if [[ ! -f "$CONFIG" ]]; then
    cat >"$CONFIG" <<'EOF'
# ~/.config/yeelight-music/config.toml
ip = "192.168.11.50"
port = 55443
music_port = 55444
bind = "192.168.11.111"
sensitivity = 1.0
smoothness = 1.0
connections = 2
EOF
  fi
}

write_config() {
  local ip="$1" port="$2" music_port="$3" bind="$4" sensitivity="$5" smoothness="$6" connections="$7"
  mkdir -p "$CONFIG_DIR"
  local tmp
  tmp="$(mktemp "$CONFIG_DIR/config.toml.XXXXXX")"
  cat >"$tmp" <<EOF
# ~/.config/yeelight-music/config.toml
ip = "$ip"
port = $port
music_port = $music_port
bind = "$bind"
sensitivity = $sensitivity
smoothness = $smoothness
connections = $connections
EOF
  mv -f "$tmp" "$CONFIG"
}

clamp_sens() {
  python3 -c 'import sys; v=float(sys.argv[1]); print(f"{min(3.0, max(0.2, v)):.1f}")' "$1"
}

icon_for() {
  python3 -c '
import sys
sens = float(sys.argv[1])
icons = sys.argv[2:]
# 0.2..3.0 → 0..len-1
t = (sens - 0.2) / (3.0 - 0.2)
idx = int(round(t * (len(icons) - 1)))
idx = max(0, min(len(icons) - 1, idx))
print(icons[idx])
' "$1" "${ICONS[@]}"
}

refresh_waybar() {
  pkill -RTMIN+"$WAYBAR_SIGNAL" waybar >/dev/null 2>&1 || true
}

reload_service() {
  if is_active; then
    systemctl --user kill -s HUP yeelight-music >/dev/null 2>&1 || true
  fi
}

restart_service_if_running() {
  if is_active; then
    systemctl --user restart yeelight-music
  fi
}

print_status() {
  ensure_config
  local ip sens smooth icon color state class hint
  ip="$(toml_get ip 192.168.11.50)"
  sens="$(toml_get sensitivity 1.0)"
  smooth="$(toml_get smoothness 1.0)"
  icon="$(icon_for "$sens")"
  if is_active; then
    color="$COLOR_ON"
    state="вкл"
    class="active"
    hint="ЛКМ: выключить"
  else
    color="$COLOR_OFF"
    state="выкл"
    class="inactive"
    hint="ЛКМ: включить"
  fi
  printf '{"text":"<span foreground='"'"'%s'"'"'>%s </span>","tooltip":"Подсветка лампы: %s\\nIP: %s\\nЧувствительность: %s\\nПлавность: %s\\n%s\\nПКМ: настройки\\nКолёсико: чувствительность","class":"%s"}\n' \
    "$color" "$icon" "$state" "$ip" "$sens" "$smooth" "$hint" "$class"
}

cmd_toggle() {
  if is_active; then
    systemctl --user stop yeelight-music
  else
    ensure_config
    systemctl --user start yeelight-music
  fi
  refresh_waybar
  print_status
}

cmd_nudge() {
  local dir="$1"
  ensure_config
  local ip port music_port bind sens smooth conns
  ip="$(toml_get ip 192.168.11.50)"
  port="$(toml_get port 55443)"
  music_port="$(toml_get music_port 55444)"
  bind="$(toml_get bind 192.168.11.111)"
  sens="$(toml_get sensitivity 1.0)"
  smooth="$(toml_get smoothness 1.0)"
  conns="$(toml_get connections 2)"
  if [[ "$dir" == up ]]; then
    sens="$(python3 -c "print(f'{float('$sens') + $SENS_STEP:.1f}')")"
  else
    sens="$(python3 -c "print(f'{float('$sens') - $SENS_STEP:.1f}')")"
  fi
  sens="$(clamp_sens "$sens")"
  write_config "$ip" "$port" "$music_port" "$bind" "$sens" "$smooth" "$conns"
  reload_service
  refresh_waybar
  print_status
}

cmd_settings() {
  ensure_config
  local ip port music_port bind sens smooth conns
  ip="$(toml_get ip 192.168.11.50)"
  port="$(toml_get port 55443)"
  music_port="$(toml_get music_port 55444)"
  bind="$(toml_get bind 192.168.11.111)"
  sens="$(toml_get sensitivity 1.0)"
  smooth="$(toml_get smoothness 1.0)"
  conns="$(toml_get connections 2)"

  local out
  if command -v yad >/dev/null 2>&1; then
    if ! out="$(
      yad --form --center --width=440 --title="Yeelight — подсветка" \
        --window-icon=preferences-system \
        --text="Настройки RGB-подсветки мониторной лампы" \
        --field="IP лампы" "$ip" \
        --field="Чувствительность:NUM" "$sens!${SENS_MIN}..${SENS_MAX}!${SENS_STEP}!1" \
        --field="Плавность:NUM" "$smooth!0.2..2.5!0.1!1" \
        --button="Отмена:1" --button="Сохранить:0"
    )"; then
      return 0
    fi
    IFS="|" read -r ip sens smooth _ <<<"$out"
  else
    # Запасной вариант, если yad ещё не в профиле (до nixos-rebuild switch).
    if ! out="$(
      zenity --forms --title="Yeelight — подсветка" --separator="|" \
        --text="Текущие значения: IP ${ip}, чувствительность ${sens}, плавность ${smooth}" \
        --add-entry="IP лампы" \
        --add-entry="Чувствительность (0.2–3.0)" \
        --add-entry="Плавность (0.2–2.5)"
    )"; then
      return 0
    fi
    local new_ip new_sens new_smooth
    IFS="|" read -r new_ip new_sens new_smooth <<<"$out"
    [[ -n "${new_ip:-}" ]] && ip="$new_ip"
    [[ -n "${new_sens:-}" ]] && sens="$new_sens"
    [[ -n "${new_smooth:-}" ]] && smooth="$new_smooth"
  fi

  ip="${ip// /}"
  if [[ ! "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    if command -v zenity >/dev/null 2>&1; then
      zenity --error --title="Yeelight — подсветка" --text="Некорректный IP: $ip" || true
    fi
    return 1
  fi
  sens="$(clamp_sens "$sens")"
  smooth="$(python3 -c 'import sys; v=float(sys.argv[1]); print(f"{min(2.5, max(0.2, v)):.1f}")' "$smooth")"
  write_config "$ip" "$port" "$music_port" "$bind" "$sens" "$smooth" "$conns"
  restart_service_if_running
  refresh_waybar
}

case "${1:-status}" in
  toggle)
    cmd_toggle
    ;;
  up)
    cmd_nudge up
    ;;
  down)
    cmd_nudge down
    ;;
  settings)
    cmd_settings
    ;;
  status | "")
    print_status
    ;;
  *)
    echo "usage: yeelight-music-toggle [status|toggle|settings|up|down]" >&2
    exit 1
    ;;
esac

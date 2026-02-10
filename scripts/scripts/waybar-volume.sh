#!/usr/bin/env bash

# Общий системный уровень громкости для Waybar
# Управляет default sink через pamixer и отдаёт JSON.

volume="$(pamixer --get-volume 2>/dev/null)"
muted="$(pamixer --get-mute 2>/dev/null)"

if [ -z "$volume" ]; then
  # pamixer не найден или ошибка — безопасный дефолт
  echo '{"text": " N/A", "tooltip": "pamixer недоступен", "class": "error"}'
  exit 0
fi

if [ "$muted" = "true" ]; then
  icon=""
  class="muted"
else
  icon=""
  class="normal"
fi

printf '{"text":"%s %s%%","tooltip":"Громкость: %s%%","class":"%s"}\n' \
  "$icon" "$volume" "$volume" "$class"


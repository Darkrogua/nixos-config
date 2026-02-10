#!/usr/bin/env bash

# Переключение default sink PipeWire/PulseAudio на следующий доступный.
# Используется из Waybar по ЛКМ на модуле громкости.

set -euo pipefail

# Получаем список sink'ов и текущий дефолт через wpctl.
mapfile -t sinks < <(wpctl status | awk '/^ \*? *[0-9]+\. .*Audio/Sink/ {print $1}')
default_id="$(wpctl status | awk '/^\*.*Audio/Sink/ {print $1}')"

# Если вдруг не нашли — выходим.
if [ "${#sinks[@]}" -eq 0 ] || [ -z "${default_id:-}" ]; then
  exit 0
fi

# Найти индекс текущего и взять следующий по кругу.
next_id="${default_id}"
for i in "${!sinks[@]}"; do
  if [ "${sinks[$i]}" = "${default_id}" ]; then
    next_index=$(( (i + 1) % ${#sinks[@]} ))
    next_id="${sinks[$next_index]}"
    break
  fi
done

wpctl set-default "${next_id}"


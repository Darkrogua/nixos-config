#!/usr/bin/env bash

# Переключение устройства вывода на следующее (циклично).
# Используем pactl и полностью опираемся на его представление
# о текущем default sink, чтобы цикл работал туда‑обратно.

set -euo pipefail

# Все sink'и (имена), которые видит PulseAudio/PipeWire.
mapfile -t sinks < <(pactl list short sinks 2>/dev/null | awk '{print $2}')

# Если меньше двух устройств вывода — переключать нечего.
if [ "${#sinks[@]}" -le 1 ]; then
  exit 0
fi

# Пытаемся взять default sink из новой команды pactl (если есть).
default_name="$(pactl get-default-sink 2>/dev/null || true)"

# Если её нет или она ничего не вернула — парсим локализованный вывод pactl info.
if [ -z "${default_name:-}" ]; then
  default_name="$(
    pactl info 2>/dev/null \
      | awk -F': ' '
          /Default Sink/ {print $2}
          /Устройство вывода по умолчанию/ {print $2}
        ' | head -n1
  )"
fi

# Если всё равно не нашли — выходим.
if [ -z "${default_name:-}" ]; then
  exit 0
fi

# Найти индекс текущего sink в списке и взять следующий по кругу.
next_name="${sinks[0]}"
for i in "${!sinks[@]}"; do
  if [ "${sinks[$i]}" = "${default_name}" ]; then
    next_index=$(( (i + 1) % ${#sinks[@]} ))
    next_name="${sinks[$next_index]}"
    break
  fi
done

# Делаем новый sink дефолтным.
pactl set-default-sink "${next_name}"

# Перемещаем все текущие потоки (sink-inputs) на новый sink,
# чтобы звук реально переехал, а не только дефолт для новых приложений.
mapfile -t inputs < <(pactl list short sink-inputs 2>/dev/null | awk '{print $1}')
for id in "${inputs[@]}"; do
  pactl move-sink-input "${id}" "${next_name}"
done


#!/usr/bin/env bash
set -euo pipefail

# В ~/Documents создаёт папку с сегодняшней датой (формат ДД.ММ.ГГ, напр. 31.01.26)
# и удаляет:
# — любую не сегодняшнюю папку с датой в имени, если она пустая;
# — любую такую папку старше 16 дней вместе с содержимым.

DOCS_DIR="${DOCS_DIR:-"$HOME/Documents"}"
RETENTION_DAYS="${RETENTION_DAYS:-16}"

mkdir -p "$DOCS_DIR"

# Фиксированный формат имён: ДД.ММ.ГГ (напр. 31.01.26)
today_name="$(date +%d.%m.%y)"
today_epoch="$(date +%s -d "$(date +%F)")"

mkdir -p "$DOCS_DIR/$today_name"

parse_dir_date_epoch() {
  # Разбирает только имена вида ДД.ММ.ГГ. Возвращает epoch (полночь) или ошибку.
  local name="$1"
  local d m yy year

  if [[ ! "$name" =~ ^([0-9]{2})\.([0-9]{2})\.([0-9]{2})$ ]]; then
    return 1
  fi
  d="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[2]}"; yy="${BASH_REMATCH[3]}"
  if (( 10#${yy} <= 50 )); then
    year="20${yy}"
  else
    year="19${yy}"
  fi
  date -d "${year}-${m}-${d}" +%s 2>/dev/null
}

is_empty_dir() {
  # Папка считается пустой, если в ней нет ни одного элемента (в т.ч. скрытых).
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  [[ "$(find "$dir" -mindepth 1 2>/dev/null | wc -l)" -eq 0 ]]
}

shopt -s nullglob
for dir in "$DOCS_DIR"/*; do
  [[ -d "$dir" ]] || continue

  name="${dir##*/}"
  dir_epoch="$(parse_dir_date_epoch "$name" || true)"
  [[ -n "${dir_epoch:-}" ]] || continue

  # Папку за сегодня не трогаем (даже если пустая).
  if [[ "$dir_epoch" == "$today_epoch" ]]; then
    continue
  fi

  # Не сегодня и пустая — удаляем независимо от возраста.
  if is_empty_dir "$dir"; then
    rm -rf -- "$dir"
    continue
  fi

  # Старше RETENTION_DAYS дней — удаляем вместе с содержимым.
  if (( (today_epoch - dir_epoch) / 86400 > RETENTION_DAYS )); then
    rm -rf -- "$dir"
  fi
done
shopt -u nullglob


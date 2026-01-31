#!/usr/bin/env bash
set -euo pipefail

# Creates today's dated folder in ~/Documents (format dd.mm.yy, e.g. 31.01.26),
# deletes:
# - any non-today dated folder that is empty
# - any non-today dated folder older than 16 days (with contents)

DOCS_DIR="${DOCS_DIR:-"$HOME/Documents"}"
RETENTION_DAYS="${RETENTION_DAYS:-16}"

mkdir -p "$DOCS_DIR"

# Fixed format: DD.MM.YY (e.g. 31.01.26)
today_name="$(date +%d.%m.%y)"
today_epoch="$(date +%s -d "$(date +%F)")"

mkdir -p "$DOCS_DIR/$today_name"

parse_dir_date_epoch() {
  # Expect directory name dd.mm.yy only. Echoes epoch (midnight) or fails.
  local name="$1"
  local d m yy year

  if [[ ! "$name" =~ ^([0-9]{2})\\.([0-9]{2})\\.([0-9]{2})$ ]]; then
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
  # Treat hidden files as content too.
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  if find "$dir" -mindepth 1 -print -quit 2>/dev/null | read -r _; then
    return 1
  fi
  return 0
}

shopt -s nullglob
for dir in "$DOCS_DIR"/*; do
  [[ -d "$dir" ]] || continue

  name="${dir##*/}"
  dir_epoch="$(parse_dir_date_epoch "$name" || true)"
  [[ -n "${dir_epoch:-}" ]] || continue

  # Keep today's folder (even if empty).
  if [[ "$dir_epoch" == "$today_epoch" ]]; then
    continue
  fi

  # If it's not today and empty -> delete regardless of age.
  if is_empty_dir "$dir"; then
    rm -rf -- "$dir"
    continue
  fi

  # If older than RETENTION_DAYS -> delete with contents.
  if (( (today_epoch - dir_epoch) / 86400 > RETENTION_DAYS )); then
    rm -rf -- "$dir"
  fi
done
shopt -u nullglob


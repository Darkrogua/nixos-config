#!/usr/bin/env bash
# Toggle GPU Screen Recorder: focused monitor + mic + desktop audio.
# Start/stop with the same command (bound to SUPER+SHIFT+R).
# On stop, save an H.264/AAC MP4 and copy it to the Wayland clipboard.

set -euo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="$RUNTIME/toggle-screen-record.pid"
PATHFILE="$RUNTIME/toggle-screen-record.path"
LOGFILE="$RUNTIME/toggle-screen-record.log"

notify_msg() {
    local summary="$1"
    local body="${2:-}"
    if command -v notify-send >/dev/null 2>&1; then
        if [[ -n "$body" ]]; then
            notify-send -t 3000 -u low "Запись экрана" "$summary"$'\n'"$body"
        else
            notify-send -t 3000 -u low "Запись экрана" "$summary"
        fi
    fi
}

videos_dir() {
    local base=""
    if command -v xdg-user-dir >/dev/null 2>&1; then
        base="$(xdg-user-dir VIDEOS 2>/dev/null || true)"
    fi
    if [[ -z "$base" ]]; then
        base="${XDG_VIDEOS_DIR:-$HOME/Videos}"
    fi
    printf '%s/Recordings' "$base"
}

focused_monitor() {
    local mon=""
    if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name' | head -n 1 || true)"
        if [[ -z "$mon" || "$mon" == "null" ]]; then
            mon="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor // empty' || true)"
        fi
    fi
    if [[ -z "$mon" || "$mon" == "null" ]]; then
        mon="screen"
    fi
    printf '%s' "$mon"
}

file_uri() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$1"
    else
        printf 'file://%s\n' "$1"
    fi
}

is_running() {
    [[ -f "$PIDFILE" ]] || return 1
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

copy_to_clipboard() {
    local file="$1"
    local uri
    uri="$(file_uri "$file")"
    # Telegram Desktop and file managers accept a file URI on text/uri-list.
    printf '%s\n' "$uri" | wl-copy -t text/uri-list
}

stop_recording() {
    local pid="" file=""
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    file="$(cat "$PATHFILE" 2>/dev/null || true)"

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -INT "$pid" 2>/dev/null || true
        local i=0
        while kill -0 "$pid" 2>/dev/null; do
            sleep 0.2
            i=$((i + 1))
            if (( i > 100 )); then
                notify_msg "Не удалось остановить запись" "процесс $pid всё ещё работает"
                return 1
            fi
        done
    fi
    rm -f "$PIDFILE" "$PATHFILE"

    if [[ -n "$file" && -s "$file" ]]; then
        if command -v wl-copy >/dev/null 2>&1; then
            copy_to_clipboard "$file"
        fi
        notify_msg "Запись сохранена и скопирована" "$file"
    else
        notify_msg "Запись остановлена, файл не найден" "${file:-}"
        return 1
    fi
}

start_recording() {
    local dir file mon
    dir="$(videos_dir)"
    mkdir -p "$dir"
    file="$dir/rec-$(date +%Y-%m-%d_%H-%M-%S).mp4"
    mon="$(focused_monitor)"

    # One merged audio track (desktop + mic) for Telegram compatibility.
    gpu-screen-recorder \
        -w "$mon" \
        -f 60 \
        -c mp4 \
        -k h264 \
        -ac aac \
        -fm cfr \
        -encoder gpu \
        -fallback-cpu-encoding yes \
        -a "default_output|default_input" \
        -o "$file" \
        >>"$LOGFILE" 2>&1 &
    local pid=$!
    disown "$pid" 2>/dev/null || true

    sleep 0.5
    if ! kill -0 "$pid" 2>/dev/null; then
        notify_msg "Не удалось начать запись" "см. $LOGFILE"
        return 1
    fi

    echo "$pid" >"$PIDFILE"
    echo "$file" >"$PATHFILE"
    notify_msg "Запись начата"
}

if is_running; then
    stop_recording
else
    rm -f "$PIDFILE" "$PATHFILE"
    start_recording
fi

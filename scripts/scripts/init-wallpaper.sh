#!/usr/bin/env bash

WP="${HOME}/Pictures/wallpapers/wallpaper"
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if ! command -v awww >/dev/null 2>&1; then
    echo "awww not in PATH" >&2
    exit 1
fi

apply() {
    awww img -t none "$WP"
}

stop_daemon() {
    pkill -TERM -x awww-daemon >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        pgrep -x awww-daemon >/dev/null || break
        sleep 0.1
    done
    pkill -KILL -x awww-daemon >/dev/null 2>&1 || true
    sleep 0.1
    rm -f "$RUNTIME"/awww*.sock "$RUNTIME"/swww*.sock 2>/dev/null || true
}

start_daemon() {
    awww-daemon --no-cache &
    for _ in $(seq 1 50); do
        if awww query >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

if awww query >/dev/null 2>&1; then
    apply
    exit 0
fi

stop_daemon
start_daemon || exit 1
apply

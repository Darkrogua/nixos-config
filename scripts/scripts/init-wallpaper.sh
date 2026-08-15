#!/usr/bin/env bash

WP="${HOME}/Pictures/wallpapers/wallpaper"
need_restart=0

if [[ "${1:-}" == "--restart" ]]; then
    need_restart=1
fi

if ! command -v awww >/dev/null 2>&1; then
    echo "awww not in PATH" >&2
    exit 1
fi

if ! awww query >/dev/null 2>&1; then
    need_restart=1
fi

if [[ "$need_restart" == 1 ]]; then
    pkill -x awww-daemon >/dev/null 2>&1 || true
    sleep 0.2
    awww-daemon --no-cache &
    for _ in $(seq 1 50); do
        if awww query >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
fi

awww img -t none "$WP"

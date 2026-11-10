#!/usr/bin/env bash

if hyprctl getoption decoration:blur:enabled | grep -E "int: 1|bool: true" > /dev/null; then
    hyprctl eval 'hl.config({ decoration = { blur = { enabled = false } } })' > /dev/null
else
    hyprctl eval 'hl.config({ decoration = { blur = { enabled = true } } })' > /dev/null
fi

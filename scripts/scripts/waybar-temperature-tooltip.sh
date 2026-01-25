#!/usr/bin/env bash

# Скрипт для отображения температуры CPU и tooltip с другими температурами в Waybar

# Функция для чтения температуры
read_temp() {
    local path=$1
    if [ -f "$path" ]; then
        local temp=$(cat "$path" 2>/dev/null | awk '{printf "%.0f", $1/1000}')
        echo "$temp"
    else
        echo "N/A"
    fi
}

# Читаем CPU температуру для основного отображения
cpu_temp=$(read_temp "/sys/class/hwmon/hwmon3/temp1_input")

# Определяем иконку и цвет в зависимости от температуры
if [ "$cpu_temp" != "N/A" ] && [ "$cpu_temp" -gt 85 ]; then
    # Температура выше 85°C - показываем огонь и красный цвет
    icon="󰈸"
    color="#CC241D"
else
    # Нормальная температура - показываем градусник и белый цвет
    icon="󰔏"
    color="#FBF1C7"
fi

# Читаем все температуры для tooltip
# hwmon0 = nvme1 (второй диск), hwmon1 = nvme0 (системный диск)
gpu_temp=$(read_temp "/sys/class/hwmon/hwmon8/temp1_input")
nvme_system_temp=$(read_temp "/sys/class/hwmon/hwmon1/temp1_input")  # nvme0 - системный
nvme_second_temp=$(read_temp "/sys/class/hwmon/hwmon0/temp1_input")  # nvme1 - второй
wifi_temp=$(read_temp "/sys/class/hwmon/hwmon6/temp1_input")

# Форматируем tooltip с экранированными переносами строк
tooltip="CPU: ${cpu_temp}°C\\nGPU: ${gpu_temp}°C\\nNVMe-1: ${nvme_system_temp}°C\\nNVMe-2: ${nvme_second_temp}°C\\nWi-Fi: ${wifi_temp}°C"

# Выводим JSON для Waybar с динамическим цветом и иконкой
echo "{\"text\": \"<span foreground='${color}'>${icon} </span><span foreground='${color}'>${cpu_temp}°C</span>\", \"tooltip\": \"${tooltip}\"}"


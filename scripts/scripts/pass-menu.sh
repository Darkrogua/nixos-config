#!/usr/bin/env bash

# Скрипт для поиска и копирования паролей из pass через rofi

PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# Получаем список всех паролей из .password-store
# Убираем расширение .gpg и путь к директории
get_passwords() {
    if [ ! -d "$PASSWORD_STORE_DIR" ]; then
        echo "Ошибка: директория $PASSWORD_STORE_DIR не найдена" >&2
        exit 1
    fi

    find "$PASSWORD_STORE_DIR" -type f -name "*.gpg" | \
        sed "s|$PASSWORD_STORE_DIR/||" | \
        sed 's|\.gpg$||' | \
        sort
}

# Показываем меню выбора пароля через rofi
select_password() {
    get_passwords | rofi -dmenu \
        -theme-str 'window {width: 50%;}' \
        -theme-str 'listview {columns: 1;}' \
        -p "🔐 Пароль:" \
        -i \
        -matching fuzzy
}

# Получаем пароль и копируем в буфер обмена
selected=$(select_password)

if [ -n "$selected" ]; then
    # Получаем пароль через pass
    password_content=$(pass "$selected" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$password_content" ]; then
        # Ищем строку с "pass:" и извлекаем значение после неё
        # Обрабатываем оба случая: "pass: значение" и "pass:значение"
        # Убираем пробелы в начале значения, если они есть
        password=$(echo "$password_content" | grep -i "pass:" | sed -n 's/.*[Pp][Aa][Ss][Ss]:[[:space:]]*\([^[:space:]].*\)/\1/p' | sed 's/^[[:space:]]*//' | head -n 1)
        
        # Если не найдено "pass:", используем первую строку как fallback
        if [ -z "$password" ]; then
            password=$(echo "$password_content" | head -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
        
        # Копируем пароль в буфер обмена
        if [ -n "$password" ]; then
            echo -n "$password" | wl-copy
            
            # Показываем уведомление (если доступно)
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "Pass" "Пароль для '$selected' скопирован в буфер обмена" -t 2000
            fi
        else
            # Показываем ошибку, если пароль не найден
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "Pass" "Пароль не найден для '$selected'" -t 3000
            fi
            exit 1
        fi
    else
        # Показываем ошибку
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "Pass" "Ошибка при получении пароля для '$selected'" -t 3000
        fi
        exit 1
    fi
fi

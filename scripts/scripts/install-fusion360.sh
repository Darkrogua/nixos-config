#!/usr/bin/env bash
# Установка Fusion 360 через скрипт cryinkfly (NixOS: патч для отсутствия snap)
# Запускайте в терминале: install-fusion360
set -e
URL="https://raw.githubusercontent.com/cryinkfly/Autodesk-Fusion-360-for-Linux/main/files/setup/autodesk_fusion_installer_x86-64.sh"
SCRIPT_NAME="autodesk_fusion_installer_x86-64.sh"
DIR="${1:-$HOME}"
SCRIPT_PATH="$DIR/$SCRIPT_NAME"

echo "Скачивание установщика..."
curl -L -o "$SCRIPT_PATH" "$URL"
chmod +x "$SCRIPT_PATH"

# Патч: в скрипте криво переопределена is_snap_firefox_installed — убираем лишний блок (NixOS нет snap)
sed -i '/^    is_snap_firefox_installed {$/,/^    }$/d' "$SCRIPT_PATH"

# Обход: подставляем фейковый snap, чтобы не было "snap: command not found"
FAKE_SNAP=$(mktemp -d)
trap 'rm -rf "$FAKE_SNAP"' EXIT
cat > "$FAKE_SNAP/snap" << 'FAKE'
#!/bin/sh
exit 0
FAKE
chmod +x "$FAKE_SNAP/snap"
export PATH="$FAKE_SNAP:$PATH"

# Кэш sudo не обязателен — установщик сам запросит пароль при необходимости
sudo -v 2>/dev/null || true
echo "Запуск установки. При запросе пароля sudo — введите его. Подтверждения: y."
cd "$DIR"
yes | ./"$SCRIPT_NAME" --install --default

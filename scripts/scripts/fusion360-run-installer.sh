#!/usr/bin/env bash
# Один раз запустить установщик Fusion 360: войти в аккаунт Autodesk и установить приложение.
# После этого обычный лаунчер будет находить Fusion360.exe.
set -e
PREFIX="$HOME/.autodesk_fusion/wineprefixes/default"
INSTALLER="$PREFIX/drive_c/users/$USER/Downloads/FusionClientInstaller.exe"

if [[ ! -f "$INSTALLER" ]]; then
  echo "Не найден установщик: $INSTALLER"
  echo "Сначала выполните: install-fusion360"
  exit 1
fi

export WINEPREFIX="$PREFIX"
echo "Запуск Fusion Client Installer — войдите в аккаунт Autodesk и установите Fusion 360."
exec wine "$INSTALLER"

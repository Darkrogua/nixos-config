{ ... }:
{
  wayland.windowManager.hyprland.settings.exec-once = [
    # "hash dbus-update-activation-environment 2>/dev/null"
    # Важно для Wayland/Electron (Cursor): прокидываем ВСЁ окружение в dbus-activation и systemd --user,
    # иначе переменные вроде NIXOS_OZONE_WL/ELECTRON_* могут не попадать в GUI приложения, запущенные из меню.
    "dbus-update-activation-environment --systemd --all"
    "systemctl --user import-environment --all"

    # Автоматическая блокировка экрана через 5 минут бездействия
    # timeout 300 = блокировка через 5 минут (300 секунд)
    # before-sleep = блокировка перед уходом в сон
    "swayidle -w timeout 300 'hyprlock' before-sleep 'hyprlock' &"

    "nm-applet &"
    "poweralertd &"
    "wl-clip-persist --clipboard both &"
    "wl-paste --watch cliphist store &"
    "waybar &"
    "swaync &"
    "udiskie --automount --notify --smart-tray &"
    "hyprctl setcursor Bibata-Modern-Ice 24 &"
    "init-wallpaper &"

    "ghostty --gtk-single-instance=true --quit-after-last-window-closed=false --initial-window=false"
    
    # Workspace 1: Telegram и Obsidian (Telegram слева, Obsidian справа)
    "[workspace 1 silent] Telegram"
    "[workspace 1 silent] obsidian"
    "sleep 2 && hyprctl dispatch workspace 1 && hyprctl dispatch focuswindow Telegram && hyprctl dispatch movewindow l && hyprctl dispatch splitratio 0.5 exact && hyprctl dispatch focuswindow obsidian && hyprctl dispatch movewindow r && hyprctl dispatch splitratio 0.5 exact &"
    
    # Workspace 2: Браузер
    "[workspace 2 silent] zen-beta"
  ];
}

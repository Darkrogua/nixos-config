{ ... }:
{
  wayland.windowManager.hyprland.settings.exec-once = [
    # "hash dbus-update-activation-environment 2>/dev/null"
    # Важно для Wayland/Electron (Cursor): прокидываем ВСЁ окружение в dbus-activation и systemd --user,
    # иначе переменные вроде NIXOS_OZONE_WL/ELECTRON_* могут не попадать в GUI приложения, запущенные из меню.
    "dbus-update-activation-environment --systemd --all"
    "systemctl --user import-environment --all"

    "hyprlock"

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
    
    # Workspace 1: Telegram и Obsidian
    "[workspace 1 silent] telegram"
    "[workspace 1 silent] obsidian"
    
    # Workspace 2: Браузер
    "[workspace 2 silent] zen-beta"
  ];
}

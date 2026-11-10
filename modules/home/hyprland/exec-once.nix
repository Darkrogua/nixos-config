{ pkgs, lib, ... }:
let
  inherit (lib.generators) mkLuaInline;
  cmds = [
    # Важно для Wayland/Electron (Cursor): прокидываем ВСЁ окружение в dbus-activation и systemd --user,
    # иначе переменные вроде NIXOS_OZONE_WL/ELECTRON_* могут не попадать в GUI приложения, запущенные из меню.
    "dbus-update-activation-environment --systemd --all"
    "systemctl --user import-environment --all"
    "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent"

    # Idle handled by hypridle (see ./hypridle.nix)

    "nm-applet"
    "poweralertd"
    "wl-clip-persist --clipboard both"
    "wl-paste --watch cliphist store"
    "waybar"
    "swaync"
    "udiskie --automount --notify --smart-tray"
    "hyprctl setcursor Bibata-Modern-Ice 24"
    "init-wallpaper"
    # Папки с датами в ~/Documents: создать сегодняшнюю и почистить старые (см. modules/home/documents-date-dirs.nix)
    "documents-date-dirs"

    "ghostty --gtk-single-instance=true --quit-after-last-window-closed=false --initial-window=false"
    "swayosd-server"
  ];

  execLine = cmd: "  hl.exec_cmd(${lib.generators.toLua { } cmd})\n";

  startFn = ''
    function()
    ${lib.concatMapStrings execLine cmds}  hl.exec_cmd("Telegram", { workspace = 1, silent = true })
      hl.exec_cmd("obsidian", { workspace = 1, silent = true })
      hl.timer(function()
        hl.dispatch(hl.dsp.focus({ workspace = 1 }))
        hl.dispatch(hl.dsp.focus({ window = "class:org.telegram.desktop" }))
        hl.dispatch(hl.dsp.window.move({ direction = "left" }))
        hl.dispatch(hl.dsp.layout("splitratio 0.5 exact"))
        hl.dispatch(hl.dsp.focus({ window = "class:obsidian" }))
        hl.dispatch(hl.dsp.window.move({ direction = "right" }))
        hl.dispatch(hl.dsp.layout("splitratio 0.5 exact"))
      end, { timeout = 2000, type = "oneshot" })
      hl.exec_cmd("zen-beta", { workspace = 2, silent = true })
    end
  '';
in
{
  wayland.windowManager.hyprland.settings = {
    on = {
      _args = [
        "hyprland.start"
        (mkLuaInline startFn)
      ];
    };
  };
}

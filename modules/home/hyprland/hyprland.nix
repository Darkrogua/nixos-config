{ pkgs, ... }:
{
  home.packages = with pkgs; [
    awww
    grimblast
    hyprpicker
    grim
    slurp
    wl-clip-persist
    cliphist
    wf-recorder
    glib
    wayland
    direnv
  ];
  systemd.user.targets.hyprland-session.Unit.Wants = [
    "xdg-desktop-autostart.target"
  ];
  
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;

    # HM при stateVersion >= 26.05 по умолчанию пишет hyprland.lua.
    # Наш settings/extraConfig всё ещё в hyprlang — без этого после апдейта
    # на Hyprland 0.55 конфиг сыпется (в .lua попадает сырой hyprlang).
    configType = "hyprlang";

    xwayland = {
      enable = true;
      # hidpi = true;
    };
    # enableNvidiaPatches = false;
    systemd.enable = true;
  };
}

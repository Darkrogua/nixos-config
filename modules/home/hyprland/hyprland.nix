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

    # Hyprland 0.57 dropped hyprlang: it only loads ~/.config/hypr/hyprland.lua
    # (and autogenerates a default one if that file is missing), ignoring
    # hyprland.conf. Home Manager must emit Lua so the compositor picks up
    # our binds, look, layout and exec-once instead of the stock example.
    configType = "lua";

    xwayland = {
      enable = true;
      # hidpi = true;
    };
    # enableNvidiaPatches = false;
    systemd.enable = true;
  };
}

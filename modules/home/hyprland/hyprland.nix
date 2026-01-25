{ pkgs, ... }:
{
  home.packages = with pkgs; [
    swww
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
  
  # Автоматический перезапуск hyprlock после пробуждения
  systemd.user.services.hyprlock-resume = {
    Unit = {
      Description = "Restart hyprlock after resume from suspend";
      After = [ "sleep.target" ];
      PartOf = [ "sleep.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.hyprlock}/bin/hyprlock";
      RemainAfterExit = false;
    };
    Install = {
      WantedBy = [ "sleep.target" ];
    };
  };
  
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;

    xwayland = {
      enable = true;
      # hidpi = true;
    };
    # enableNvidiaPatches = false;
    systemd.enable = true;
  };
}

{ pkgs, ... }:
{
  home.packages = with pkgs; [
    hypridle
  ];

  # Hypridle config (Hyprlang)
  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
      # Safety: lock screen before suspend triggered elsewhere
      before_sleep_cmd = hyprlock
    }

    # После 5 минут (60*5 = 300) выключаем экран
    listener {
      timeout = 300
      on-timeout = hyprctl dispatch dpms off
      on-resume = hyprctl dispatch dpms on
    }

    # После 15 минут уходим в сон 
    listener {
      timeout = 900
      on-timeout = hyprlock & sleep 2; systemctl suspend
    }
  '';

  # Prefer systemd user service over exec-once background jobs
  systemd.user.services.hypridle = {
    Unit = {
      Description = "Hypridle idle management daemon";
      PartOf = [ "hyprland-session.target" ];
      After = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.hypridle}/bin/hypridle -c %h/.config/hypr/hypridle.conf";
      Restart = "on-failure";
      RestartSec = 1;
    };
    Install = {
      WantedBy = [ "hyprland-session.target" ];
    };
  };
}


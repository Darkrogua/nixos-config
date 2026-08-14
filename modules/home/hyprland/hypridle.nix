{ pkgs, ... }:
{
  home.packages = with pkgs; [
    hypridle
  ];

  # Hypridle: wiki-схема (lock через loginctl → lock_cmd).
  # after_sleep: dpms on + если hyprlock умер на resume — снова lock.
  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
      lock_cmd = pidof hyprlock || hyprlock
      before_sleep_cmd = loginctl lock-session
      after_sleep_cmd = hyprctl dispatch dpms on; pidof hyprlock || loginctl lock-session
    }

    # После 5 минут (60*5 = 300) выключаем экран
    listener {
      timeout = 300
      on-timeout = hyprctl dispatch dpms off
      on-resume = hyprctl dispatch dpms on
    }

    # После 15 минут уходим в сон.
    # Lock перед suspend — before_sleep_cmd / lock_cmd.
    listener {
      timeout = 900
      on-timeout = systemctl suspend
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


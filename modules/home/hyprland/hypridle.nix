{ pkgs, config, ... }:
let
  initWallpaper = "${config.home.profileDirectory}/bin/init-wallpaper";
in
{
  home.packages = with pkgs; [
    hypridle
  ];

  # Hypridle: wiki-схема (lock через loginctl → lock_cmd).
  # Обои awww после сна часто пропадают — ставим снова после unlock, не на lock-экране.
  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
      lock_cmd = pidof hyprlock || hyprlock
      before_sleep_cmd = loginctl lock-session
      after_sleep_cmd = hyprctl dispatch dpms on; pidof hyprlock || loginctl lock-session
      on_unlock_cmd = sh -c '${initWallpaper} --restart; systemctl --user restart ma-touch'
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
      Environment = "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin";
      Restart = "on-failure";
      RestartSec = 1;
    };
    Install = {
      WantedBy = [ "hyprland-session.target" ];
    };
  };
}


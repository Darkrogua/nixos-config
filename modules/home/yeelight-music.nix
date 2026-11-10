{ pkgs, ... }:
{
  home.packages = [
    pkgs.yeelight-music
    pkgs.yad
  ];

  # Автозапуск при входе в графическую сессию. Выключение с waybar
  # (systemctl --user stop) действует до конца сессии / следующего входа.
  # Настройки: ~/.config/yeelight-music/config.toml
  systemd.user.services.yeelight-music = {
    Unit = {
      Description = "Подсветка RGB-фона Yeelight под музыку";
      After = [
        "graphical-session.target"
        "pipewire-pulse.service"
      ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.yeelight-music}/bin/yeelight-music";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 15;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}

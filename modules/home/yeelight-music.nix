{ pkgs, ... }:
{
  home.packages = [
    pkgs.yeelight-music
    pkgs.yad
  ];

  # Не ставится в автозапуск: включать с waybar (ЛКМ) или:
  #   systemctl --user start yeelight-music
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
      RestartSec = 3;
    };
  };
}

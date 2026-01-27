{ pkgs, ... }:
let
  # Создаем wrapper скрипт для Postman с правильными флагами Wayland
  # и отключением автообновления (в NixOS обновления управляются через nix)
  postman-wrapper = pkgs.writeShellScriptBin "postman" ''
    export ELECTRON_DISABLE_AUTO_UPDATE=1
    exec ${pkgs.postman}/bin/postman \
      --enable-features=UseOzonePlatform \
      --ozone-platform=wayland \
      --disable-gpu-sandbox \
      --disable-updates \
      "$@"
  '';
in
{
  # Добавляем wrapper скрипт в PATH
  home.packages = [ postman-wrapper ];

  # Переопределяем desktop файл Postman с правильными флагами Wayland
  # для устранения ошибок GPU буферов в Wayland окружении
  xdg.desktopEntries.postman = {
    name = "Postman";
    genericName = "API Client";
    exec = "postman %U";
    icon = "postman";
    terminal = false;
    categories = [ "Development" "Network" ];
    mimeType = [ "x-scheme-handler/postman" ];
  };
}

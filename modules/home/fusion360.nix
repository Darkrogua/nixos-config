# Пункт меню для Autodesk Fusion 360 (установлен скриптом cryinkfly в ~/.autodesk_fusion)
{ config, pkgs, ... }:
let
  home = config.home.homeDirectory;
  fusionBin = "${home}/.autodesk_fusion/bin/autodesk_fusion_launcher.sh";
  fusionIcon = "${home}/.autodesk_fusion/resources/graphics/autodesk_fusion.svg";

  # Обёртка: запуск строго из $HOME, чтобы Wine не получал unix\...\nixos-config как CWD
  wrapperScript = ''
    #!/usr/bin/env bash
    exec env -C "$HOME" "${fusionBin}" "$@"
  '';

  # Обёртка при ошибке — уведомление
  fusion360-launch = pkgs.writeScriptBin "fusion360-launch" ''
    export PATH="${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.libnotify ]}:$PATH"
    if ! "${home}/.local/bin/fusion360-wrapper.sh" 2>/dev/null; then
      notify-send -u critical "Fusion 360" "Не удалось запустить. Сначала выполните в терминале:\nWINEPREFIX=$HOME/.autodesk_fusion/wineprefixes/default wine $HOME/.autodesk_fusion/wineprefixes/default/drive_c/users/$USER/Downloads/FusionClientInstaller.exe\n(войти в аккаунт Autodesk и установить приложение)"
      exit 1
    fi
  '';

  desktopFile = ''
    [Desktop Entry]
    Type=Application
    Name=Autodesk Fusion 360
    GenericName=CAD/CAM
    Exec=${home}/.local/bin/fusion360-wrapper.sh
    Icon=${fusionIcon}
    Terminal=true
    Categories=Graphics;Engineering;3DGraphics;
  '';
in
{
  home.packages = [ fusion360-launch ];

  home.file.".local/bin/fusion360-wrapper.sh" = {
    executable = true;
    text = wrapperScript;
  };

  home.file.".local/share/applications/autodesk-fusion360.desktop" = {
    text = desktopFile;
  };
}

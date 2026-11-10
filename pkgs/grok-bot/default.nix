{
  lib,
  fetchurl,
  appimageTools,
}:

let
  pname = "grok-bot";
  version = "0.79.3";

  src = fetchurl {
    url = "https://downloads.cursor.com/grokbot/stable/473941287261c3efa92c6b2a0bf7e1caad1a2ef2/linux/x64/Grok_Bot_${version}.AppImage";
    hash = "sha256-ZPOEIKH2UJu7kBrJ3aoKdBi9B0ZSyDvPQlzJqL93Odg=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/${pname}.desktop -t $out/share/applications
    cp -a ${appimageContents}/usr/share/icons $out/share/

    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox -- %U' \
      'Exec=${pname} --no-sandbox --ozone-platform-hint=auto %U'
  '';

  meta = {
    description = "Grok Bot desktop app";
    homepage = "https://cursor.com/download/bot";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "grok-bot";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

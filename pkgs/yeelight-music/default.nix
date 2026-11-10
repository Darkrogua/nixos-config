{
  lib,
  rustPlatform,
  pkg-config,
  libpulseaudio,
}:

rustPlatform.buildRustPackage {
  pname = "yeelight-music";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: type:
      let
        base = baseNameOf path;
      in
      lib.cleanSourceFilter path type && base != "target";
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libpulseaudio ];

  meta = {
    description = "Подсветка RGB-фона Yeelight под музыку (системный звук)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "yeelight-music";
  };
}

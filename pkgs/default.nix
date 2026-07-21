{
  inputs,
  pkgs,
  ...
}:
{
  _2048 = pkgs.callPackage ./2048 {
    stdenv = pkgs.gcc14Stdenv;
  };
  maple-mono-custom = pkgs.callPackage ./maple-mono { inherit inputs; };

  # Актуальный Cursor из отдельного nixpkgs-cursor (не тащит весь апдейт системы)
  code-cursor =
    (import inputs.nixpkgs-cursor {
      system = pkgs.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    }).code-cursor;
}

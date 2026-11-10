{ pkgs, ... }:
{
  fonts = {
    enableDefaultPackages = true;
    fontconfig.enable = true;
    packages = with pkgs; [
      jetbrains-mono
      dejavu_fonts
      noto-fonts
    ];
  };
}

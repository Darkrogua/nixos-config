{ pkgs, ... }:
{
  programs = {
    dconf.enable = true;
    zsh.enable = true;
    appimage.enable = true;
    appimage.binfmt = true;

    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = pkgs.pinentry-gnome3;  # Для Wayland используем gnome3, можно также pinentry-gtk2 или pinentry-qt
    };

    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [ ];
  };
}

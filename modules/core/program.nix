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
      # pinentryFlavor = "";
    };

    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [ ];
  };
}

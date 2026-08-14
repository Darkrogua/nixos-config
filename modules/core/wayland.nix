{ pkgs, ... }:
{
  programs.hyprland = {
    enable = true;
  };

  xdg.portal = {
    enable = true;
    # false: Electron (Obsidian и др.) иначе не открывает http(s) через portal
    xdgOpenUsePortal = false;
    config = {
      common.default = [ "gtk" ];
      hyprland.default = [
        "gtk"
        "hyprland"
      ];
    };

    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
}

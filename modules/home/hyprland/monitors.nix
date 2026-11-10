{ pkgs, ... }:
{
  wayland.windowManager.hyprland.settings = {
    monitor = {
      output = "";
      mode = "preferred";
      position = "auto";
      scale = "auto";
    };
  };

  home.packages = with pkgs; [ nwg-displays ];
}

{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ## Multimedia
    audacity
    gimp
    media-downloader
    obs-studio
    pavucontrol
    soundwireserver
    video-trimmer
    vlc

    ## Office
    libreoffice
    gnome-calculator

    ## Utility
    blueman
    dconf-editor
    gnome-disk-utility
    popsicle
    mission-center # GUI resources monitor
    zenity
    
    ## Base
    telegram-desktop

    ## Browser
    google-chrome                    # Google Chrome browser

    ## Work
    insomnia
    # postman управляется через modules/home/postman.nix с настройками Wayland
    jetbrains.phpstorm
    code-cursor
    
  ];
}

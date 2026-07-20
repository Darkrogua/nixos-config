{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ## Multimedia
    audacity
    blender
    gimp
    prusa-slicer       # слайсер для 3D-печати
    media-downloader
    qbittorrent
    obs-studio
    pavucontrol
    soundwireserver
    video-trimmer
    vlc

    ## Office
    libreoffice
    gnome-calculator

    ## Utility
    amnezia-vpn
    blueman
    dconf-editor
    guake
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
    filezilla
    # postman управляется через modules/home/postman.nix с настройками Wayland
    jetbrains.phpstorm
    code-cursor
    
  ];
}

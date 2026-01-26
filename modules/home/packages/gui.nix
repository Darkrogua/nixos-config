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

    ## Work
    insomnia                          # REST API client
    postman                           # REST API client
    jetbrains.phpstorm
    code-cursor
    
  ];
}

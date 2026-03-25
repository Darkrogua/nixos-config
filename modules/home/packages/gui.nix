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
    gnome-disk-utility
    popsicle
    mission-center # GUI resources monitor
    zenity
    
    ## Base
    telegram-desktop

    ## Browser
    google-chrome                    # Google Chrome browser

    ## Fusion 360 installer deps (cryinkfly script)
    p7zip
    cabextract
    yad
    gettext          # скрипт использует gettext
    bc               # калькулятор в скрипте
    mesa-demos       # glxinfo
    mokutil          # проверка Secure Boot
    lsb-release      # lsb_release для скрипта
    samba            # samba, wbinfo — скрипт проверяет наличие

    ## Work
    insomnia
    filezilla
    # postman управляется через modules/home/postman.nix с настройками Wayland
    jetbrains.phpstorm
    code-cursor
    
  ];
}

{ ... }:
{
  wayland.windowManager.hyprland.settings = {
    window_rule = [
      { name = "float-imv"; match.class = "^(imv)$"; float = true; }
      { name = "float-mpv"; match.class = "^(mpv)$"; float = true; }
      { name = "float-zenity"; match.class = "^(zenity)$"; float = true; }
      { name = "float-waypaper"; match.class = "^(waypaper)$"; float = true; }
      { name = "float-soundwire"; match.class = "^(SoundWireServer)$"; float = true; }
      { name = "float-sameboy"; match.class = "^(.sameboy-wrapped)$"; float = true; }
      { name = "float-calculator"; match.class = "^(org.gnome.Calculator)$"; float = true; }
      { name = "float-fileroller"; match.class = "^(org.gnome.FileRoller)$"; float = true; }
      { name = "float-pavucontrol"; match.class = "^(org.pulseaudio.pavucontrol)$"; float = true; }

      { name = "pin-rofi"; match.class = "^(rofi)$"; pin = true; }
      { name = "pin-waypaper"; match.class = "^(waypaper)$"; pin = true; }

      { name = "tile-aseprite"; match.class = "^(Aseprite)$"; tile = true; }

      { name = "size-zenity"; match.class = "^(zenity)$"; size = "850 500"; }
      { name = "size-soundwire"; match.class = "^(SoundWireServer)$"; size = "725 330"; }

      { name = "size-volume-control"; match.title = "^(Volume Control)$"; size = "700 450"; }
      { name = "move-volume-control"; match.title = "^(Volume Control)$"; move = "40 55%"; }

      { name = "pin-pip"; match.title = "^(Picture-in-Picture)$"; pin = true; }
      { name = "float-pip"; match.title = "^(Picture-in-Picture)$"; float = true; }

      # Workspace 1: Telegram и Obsidian
      { name = "ws-telegram"; match.class = "^(Telegram)$"; workspace = 1; }
      { name = "ws-telegramdesktop"; match.class = "^(TelegramDesktop)$"; workspace = 1; }
      { name = "ws-telegram-desktop"; match.class = "^(telegram-desktop)$"; workspace = 1; }
      { name = "ws-obsidian"; match.class = "^(obsidian)$"; workspace = 1; }
      { name = "ws-zen-beta"; match.class = "^(zen-beta)$"; workspace = 2; }
      { name = "ws-gimp"; match.class = "^(Gimp-2.10)$"; workspace = 4; }
      { name = "ws-aseprite"; match.class = "^(Aseprite)$"; workspace = 4; }
      { name = "ws-audacious"; match.class = "^(Audacious)$"; workspace = 5; }
      { name = "ws-spotify"; match.class = "^(Spotify)$"; workspace = 5; }
      { name = "ws-obs"; match.class = "^(com.obsproject.Studio)$"; workspace = 8; }
      { name = "ws-discord"; match.class = "^(discord)$"; workspace = 10; }
      { name = "ws-webcord"; match.class = "^(WebCord)$"; workspace = 10; }
      { name = "ws-vesktop"; match.class = "^(vesktop)$"; workspace = 10; }

      { name = "idle-mpv"; match.class = "^(mpv)$"; idle_inhibit = "focus"; }
      { name = "idle-youtube"; match = { class = "^(zen-beta)$"; title = "^(.*YouTube.*)$"; }; idle_inhibit = "focus"; }
      { name = "idle-zen-fs"; match.class = "^(zen)$"; idle_inhibit = "fullscreen"; }

      { name = "dim-portal"; match.class = "^(xdg-desktop-portal-gtk)$"; dim_around = true; }

      { name = "xwayland-rounding"; match.xwayland = true; rounding = 0; }

      # No gaps when only
      { name = "no-gaps-border-wtv1"; match = { float = false; workspace = "w[tv1]"; }; border_size = 0; }
      { name = "no-gaps-rounding-wtv1"; match = { float = false; workspace = "w[tv1]"; }; rounding = 0; }
      { name = "no-gaps-border-f1"; match = { float = false; workspace = "f[1]"; }; border_size = 0; }
      { name = "no-gaps-rounding-f1"; match = { float = false; workspace = "f[1]"; }; rounding = 0; }
    ];

    layer_rule = [
      { name = "dim-rofi"; match.namespace = "rofi"; dim_around = true; }
      { name = "dim-swaync"; match.namespace = "swaync-control-center"; dim_around = true; }
    ];

    # No gaps when only
    workspace_rule = [
      { workspace = "w[tv1]"; gaps_out = 0; gaps_in = 0; }
      { workspace = "f[1]"; gaps_out = 0; gaps_in = 0; }
      { workspace = "1"; gaps_out = 0; gaps_in = 0; }
    ];
  };
}

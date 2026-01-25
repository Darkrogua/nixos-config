{ host, lib, pkgs, ... }:
let
  custom = {
    font = "Maple Mono";
    font_size = "18px";
    font_weight = "bold";
    text_color = "#FBF1C7";
    background_0 = "#1D2021";
    background_1 = "#282828";
    border_color = "#928374";
    red = "#CC241D";
    green = "#98971A";
    yellow = "#FABD2F";
    blue = "#458588";
    magenta = "#B16286";
    cyan = "#689D6A";
    orange = "#D65D0E";
    opacity = "1";
    indicator_height = "2px";
  };
in
{
  programs.waybar.settings.mainBar = with custom; {
    position = "bottom";
    layer = "top";
    height = 28;
    margin-top = 0;
    margin-bottom = 0;
    margin-left = 0;
    margin-right = 0;
    modules-left = [
      "custom/launcher"
      "hyprland/workspaces"
      "tray"
    ];
    modules-center = [
      "clock"
    ];
    # NB: избегаем пустых строк (иначе Waybar ругается "Unknown module" / "Item ''")
    modules-right =
      [
        "custom/temperature"
        "cpu"
        "memory"
      ]
      ++ (lib.optional (host == "desktop") "disk")
      ++ [
        "pulseaudio"
        "network"
        # "battery"  # Закомментировано: не нужен на десктопе
        "hyprland/language"
        "custom/notification"
        "custom/power-menu"
      ];
    clock = {
      calendar = {
        format = {
          today = "<span color='#98971A'><b>{}</b></span>";
        };
      };
      interval = 1;
      # Пример: "пн 17 19:57"
      # По мануалу waybar-clock(5): locale задаётся прямо тут, чтобы strftime (%a/%B) был на нужном языке
      # и чтобы {calendar} корректно определял начало недели.
      # Если clock пропадёт и в логах будет locale::facet...name not valid — значит локаль не сгенерирована.
      # В Waybar часто требуется формат xx_YY.utf8 (см. issue #2694)
      locale = "ru_RU.utf8";
      # Важно (см. issue #2694): добавляем флаг L, иначе форматирование может оставаться в "C" локали
      format = "{:L%a %d %H:%M}";
      tooltip = "true";
      tooltip-format = "<big>{:L%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      # По клику (alt): "17 января" (без времени)
      format-alt = "{:L%d %B}";
    };

    "hyprland/workspaces" = {
      active-only = false;
      disable-scroll = true;
      format = "{icon}";
      on-click = "activate";
      format-icons = {
        "1" = "1";
        "2" = "2";
        "3" = "3";
        "4" = "4";
        "5" = "5";
        "6" = "6";
        "7" = "7";
        "8" = "8";
        "9" = "9";
        "10" = "10";
        sort-by-number = true;
      };
  
      persistent-workspaces = {
        "1" = [ ];

      };
    };
    "custom/temperature" = {
      exec = "${pkgs.writeShellScript "waybar-temperature-tooltip" (builtins.readFile ../../../scripts/scripts/waybar-temperature-tooltip.sh)}";
      interval = 2;
      return-type = "json";
    };
    cpu = {
      format = "<span foreground='${green}'> </span> {usage}%";
      format-alt = "<span foreground='${green}'> </span> {avg_frequency} GHz";
      interval = 2;
      on-click-right = "hyprctl dispatch exec '[float; center; size 950 650] kitty --override font_size=14 --title float_kitty btop'";
    };
    memory = {
      format = "<span foreground='${cyan}'>󰟜 </span>{used} GiB";
      format-alt = "<span foreground='${cyan}'>󰟜 </span>{}%";
      interval = 2;
      on-click-right = "hyprctl dispatch exec '[float; center; size 950 650] kitty --override font_size=14 --title float_kitty btop'";
    };
    disk = {
      # path = "/";
      format = "<span foreground='${orange}'>󰋊 </span>{percentage_used}%";
      interval = 60;
      on-click-right = "hyprctl dispatch exec '[float; center; size 950 650] kitty --override font_size=14 --title float_kitty btop'";
    };
    network = {
      format-wifi = "<span foreground='${magenta}'> </span> {signalStrength}%";
      format-ethernet = "<span foreground='${magenta}'>󰀂 </span>";
      tooltip-format = "Connected to {essid} {ifname} via {gwaddr}";
      format-linked = "{ifname} (No IP)";
      format-disconnected = "<span foreground='${magenta}'>󰖪 </span>";
    };
    tray = {
      icon-size = 20;
      spacing = 12;
    };
    pulseaudio = {
      format = "{icon} {volume}%";
      format-muted = "<span foreground='${blue}'> </span> {volume}%";
      format-icons = {
        default = [ "<span foreground='${blue}'> </span>" ];
      };
      scroll-step = 2;
      # ЛКМ: открываем выбор устройства/настройки звука (а не mute)
      on-click = "pavucontrol";
      # ПКМ: mute/unmute
      on-click-right = "pamixer -t";
    };

    # battery = {
    #   # Только иконка (без процентов)
    #   format = "<span foreground='${yellow}'>{icon}</span>";
    #   # Вертикальная иконка: поворачиваем модуль (встроенная опция Waybar)
    #   rotate = 90;
    #   format-icons = [
    #     " "
    #     " "
    #     " "
    #     " "
    #     " "
    #   ];
    #   format-charging = "<span foreground='${yellow}'> </span>";
    #   format-full = "<span foreground='${yellow}'> </span>";
    #   format-warning = "<span foreground='${yellow}'> </span>";
    #   interval = 5;
    #   states = {
    #     warning = 20;
    #   };
    #   format-time = "{H}h{M}m";
    #   tooltip = true;
    #   tooltip-format = "{time}";
    # };
    "hyprland/language" = {
      tooltip = true;
      tooltip-format = "Keyboard layout";
      format = "<span foreground='#FABD2F'> </span> {}";
      format-ru = "RU";
      format-en = "US";
      on-click = "hyprctl switchxkblayout at-translated-set-2-keyboard next";
    };
    "custom/launcher" = {
      format = "";
      on-click = "random-wallpaper";
      on-click-right = "rofi -show drun";
      tooltip = "true";
      tooltip-format = "Random Wallpaper";
    };
    "custom/notification" = {
      tooltip = true;
      tooltip-format = "Notifications";
      format = "{icon}";
      format-icons = {
        notification = "<span foreground='red'><sup></sup></span>";
        none = "";
        dnd-notification = "<span foreground='red'><sup></sup></span>";
        dnd-none = "";
        inhibited-notification = "<span foreground='red'><sup></sup></span>";
        inhibited-none = "";
        dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
        dnd-inhibited-none = "";
      };
      return-type = "json";
      exec-if = "which swaync-client";
      exec = "swaync-client -swb";
      on-click = "swaync-client -t -sw";
      on-click-right = "swaync-client -d -sw";
      escape = true;
    };
    "custom/power-menu" = {
      tooltip = true;
      tooltip-format = "Power menu";
      format = "<span foreground='${red}'> </span>";
      on-click = "power-menu";
    };
  };
}

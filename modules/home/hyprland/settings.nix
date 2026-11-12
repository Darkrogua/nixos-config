{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    env = [
      { _args = [ "NIXOS_OZONE_WL" "1" ]; }
      { _args = [ "ELECTRON_OZONE_PLATFORM_HINT" "wayland" ]; }
      { _args = [ "OZONE_PLATFORM" "wayland" ]; }
    ];

    config = {
      input = {
        kb_layout = "us,ru";
        kb_options = "grp:caps_toggle";

        repeat_delay = 300;
        numlock_by_default = true;

        follow_mouse = 0;
        mouse_refocus = false;
        float_switch_override_focus = 0;

        touchpad = {
          disable_while_typing = false;
          natural_scroll = true;
        };
      };

      general = {
        layout = "dwindle";

        gaps_in = 0;
        gaps_out = 0;
        border_size = 2;

        col = {
          active_border = {
            colors = [ "rgb(98971A)" "rgb(CC241D)" ];
            angle = 45;
          };
          inactive_border = "0x00000000";
        };
      };

      # Монитор SAC G7c II умеет HDR: при полноэкранном видео Hyprland сам
      # переключал его в HDR (чёрный экран на пару секунд, потом блеклая картинка).
      render = {
        cm_auto_hdr = 0;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;

        focus_on_activate = true;
        middle_click_paste = false;

        disable_autoreload = true;
        allow_session_lock_restore = true;
      };

      dwindle = {
        force_split = 2;
        preserve_split = true;
        use_active_for_splits = true;
      };

      master = {
        new_status = "master";
      };

      decoration = {
        rounding = 0;

        active_opacity = 1.0;
        inactive_opacity = 1.0;

        blur = {
          enabled = false;

          size = 3;
          noise = 0;
          passes = 2;
          contrast = 1.4;
          brightness = 1;

          xray = true;
        };

        shadow = {
          enabled = true;

          range = 20;
          render_power = 3;

          offset = [ 0 2 ];
          color = "rgba(00000055)";
        };
      };

      animations = {
        enabled = true;
      };

      binds = {
        scroll_event_delay = 100;
        movefocus_cycles_fullscreen = true;
      };

      xwayland = {
        force_zero_scaling = true;
      };
    };

    curve = [
      { _args = [ "fluent_decel" { type = "bezier"; points = [ [ 0 0.2 ] [ 0.4 1 ] ]; } ]; }
      { _args = [ "easeOutCirc" { type = "bezier"; points = [ [ 0 0.55 ] [ 0.45 1 ] ]; } ]; }
      { _args = [ "easeOutCubic" { type = "bezier"; points = [ [ 0.33 1 ] [ 0.68 1 ] ]; } ]; }
      { _args = [ "fade_curve" { type = "bezier"; points = [ [ 0 0.55 ] [ 0.45 1 ] ]; } ]; }
    ];

    animation = [
      { leaf = "windowsIn"; enabled = false; speed = 4; bezier = "easeOutCubic"; style = "popin 20%"; }
      { leaf = "windowsOut"; enabled = false; speed = 4; bezier = "fluent_decel"; style = "popin 80%"; }
      { leaf = "windowsMove"; enabled = true; speed = 2; bezier = "fluent_decel"; style = "slide"; }
      { leaf = "fadeIn"; enabled = true; speed = 3; bezier = "fade_curve"; }
      { leaf = "fadeOut"; enabled = true; speed = 3; bezier = "fade_curve"; }
      { leaf = "fadeSwitch"; enabled = false; speed = 1; bezier = "easeOutCirc"; }
      { leaf = "fadeShadow"; enabled = true; speed = 10; bezier = "easeOutCirc"; }
      { leaf = "fadeDim"; enabled = true; speed = 4; bezier = "fluent_decel"; }
      { leaf = "workspaces"; enabled = true; speed = 4; bezier = "easeOutCubic"; style = "fade"; }
    ];
  };
}

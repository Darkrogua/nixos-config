{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [ swayosd ];

  wayland.windowManager.hyprland.settings.bind =
    let
      inherit (lib.generators) mkLuaInline;
      luaStr = s: "\"" + lib.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] s + "\"";
      exec = cmd: "hl.dsp.exec_cmd(${luaStr cmd})";
      bind = keys: dsp: opts: { _args = [ keys (mkLuaInline dsp) opts ]; };
    in
    [
      (bind "XF86AudioMute" (exec "swayosd-client --output-volume mute-toggle") { })
      # binds active in lockscreen
      (bind "XF86MonBrightnessUp" (exec "swayosd-client --brightness raise 5%+") { locked = true; })
      (bind "XF86MonBrightnessDown" (exec "swayosd-client --brightness lower 5%-") { locked = true; })
      (bind "SUPER + XF86MonBrightnessUp" (exec "brightnessctl set 100%") { locked = true; })
      (bind "SUPER + XF86MonBrightnessDown" (exec "brightnessctl set 0%") { locked = true; })
      (bind "XF86AudioRaiseVolume" (exec "swayosd-client --output-volume +2 --max-volume=100") { locked = true; repeating = true; })
      (bind "XF86AudioLowerVolume" (exec "swayosd-client --output-volume -2") { locked = true; repeating = true; })
      (bind "SUPER + f11" (exec "swayosd-client --output-volume +2 --max-volume=100") { locked = true; repeating = true; })
      (bind "SUPER + f12" (exec "swayosd-client --output-volume -2") { locked = true; repeating = true; })
      (bind "CAPS + Caps_Lock" (exec "swayosd-client --caps-lock") { release = true; })
      (bind "Scroll_Lock" (exec "swayosd-client --scroll-lock") { release = true; })
      (bind "Num_Lock" (exec "swayosd-client --num-lock") { release = true; })
    ];

  xdg.configFile."swayosd/style.css".text = ''
    window {
        padding: 0px 10px;
        border-radius: 25px;
        border: 10px;
        background: alpha(#282828, 0.99);
    }

    #container {
        margin: 15px;
    }

    image, label {
        color: #FBF1C7;
    }

    progressbar:disabled,
    image:disabled {
        opacity: 0.95;
    }

    progressbar {
        min-height: 6px;
        border-radius: 999px;
        background: transparent;
        border: none;
    }
    trough {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: alpha(#DDDDDD, 0.2);
    }
    progress {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: #FBF1C7;
    }
  '';
}

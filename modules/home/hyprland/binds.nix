{ lib, ... }:
let
  inherit (lib.generators) mkLuaInline;
  luaStr = s: "\"" + lib.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] s + "\"";
  exec = cmd: "hl.dsp.exec_cmd(${luaStr cmd})";
  execRules = cmd: rules: "hl.dsp.exec_cmd(${luaStr cmd}, ${rules})";
  bind = keys: dsp: { _args = [ keys (mkLuaInline dsp) ]; };
  bindOpts = keys: dsp: opts: { _args = [ keys (mkLuaInline dsp) opts ]; };
in
{
  wayland.windowManager.hyprland.settings = {
    bind = [
      # show keybinds list
      (bind "SUPER + F1" (exec "show-keybinds"))

      # keybindings
      (bind "SUPER + Return" (exec "ghostty --gtk-single-instance=true"))
      (bind "ALT + Return" (execRules "ghostty" "{ float = true, size = \"1111 700\" }"))
      (bind "SUPER + SHIFT + Return" (execRules "ghostty" "{ fullscreen = true }"))
      (bind "SUPER + B" (execRules "zen-beta" "{ workspace = 1, silent = true }"))
      (bind "SUPER + Q" "hl.dsp.window.close()")
      (bind "SUPER + F" "hl.dsp.window.fullscreen({ mode = \"fullscreen\" })")
      (bind "SUPER + SHIFT + F" "hl.dsp.window.fullscreen({ mode = \"maximized\" })")
      (bind "SUPER + Space" (exec "toggle-float"))
      (bind "SUPER + D" (exec "toggle-rofi rofi -show drun"))
      (bind "SUPER + SHIFT + D" (exec "vesktop --enable-features=UseOzonePlatform --ozone-platform=wayland"))
      (bind "SUPER + SHIFT + S" (execRules "SoundWireServer" "{ workspace = 5, silent = true }"))
      (bind "SUPER + Escape" (exec "swaylock"))
      (bind "ALT + Escape" (exec "loginctl lock-session"))
      (bind "SUPER + SHIFT + Escape" (exec "power-menu"))
      (bind "SUPER + P" "hl.dsp.window.pseudo()")
      (bind "SUPER + SHIFT + P" (exec "pass-menu"))
      # Hyprland 0.55+: togglesplit только через layoutmsg
      (bind "SUPER + X" "hl.dsp.layout(\"togglesplit\")")
      (bind "SUPER + T" (exec "toggle-oppacity"))
      (bind "SUPER + E" (exec "nemo"))
      (bind "ALT + E" (execRules "nemo" "{ float = true, size = \"1111 700\" }"))
      (bind "SUPER + SHIFT + B" (exec "toggle-waybar"))
      (bind "SUPER + C" (exec "hyprpicker -a"))
      (bind "SUPER + W" (exec "wallpaper-picker"))
      (bind "SUPER + SHIFT + W" (execRules "waypaper" "{ float = true, size = \"925 615\" }"))
      (bind "SUPER + N" (exec "swaync-client -t -sw"))
      (bind "CTRL + SHIFT + Escape" (execRules "missioncenter" "{ workspace = 9 }"))
      (bind "SUPER + equal" (exec "woomer"))

      # screenshot
      (bind "Print" (exec "screenshot --copy"))
      (bind "SUPER + Print" (exec "screenshot --save"))
      (bind "SUPER + SHIFT + Print" (exec "screenshot --swappy"))

      # screen recording (focused monitor + mic + desktop audio)
      (bind "SUPER + SHIFT + R" (exec "toggle-screen-record"))

      # switch focus
      (bind "SUPER + left" "hl.dsp.focus({ direction = \"left\" })")
      (bind "SUPER + right" "hl.dsp.focus({ direction = \"right\" })")
      (bind "SUPER + up" "hl.dsp.focus({ direction = \"up\" })")
      (bind "SUPER + down" "hl.dsp.focus({ direction = \"down\" })")
      (bind "SUPER + h" "hl.dsp.focus({ direction = \"left\" })")
      (bind "SUPER + j" "hl.dsp.focus({ direction = \"down\" })")
      (bind "SUPER + k" "hl.dsp.focus({ direction = \"up\" })")
      # сон (Mod+L) — lock до появления hyprlock, потом suspend
      (bind "SUPER + code:46" (exec "sh -c 'hypr-sleep prepare; systemctl suspend'"))

      (bind "SUPER + left" "hl.dsp.window.alter_zorder({ mode = \"top\" })")
      (bind "SUPER + right" "hl.dsp.window.alter_zorder({ mode = \"top\" })")
      (bind "SUPER + up" "hl.dsp.window.alter_zorder({ mode = \"top\" })")
      (bind "SUPER + down" "hl.dsp.window.alter_zorder({ mode = \"top\" })")
      (bind "SUPER + h" "hl.dsp.window.alter_zorder({ mode = \"top\" })")
      (bind "SUPER + j" "hl.dsp.window.alter_zorder({ mode = \"top\" })")
      (bind "SUPER + k" "hl.dsp.window.alter_zorder({ mode = \"top\" })")

      (bind "CTRL + ALT + up" "hl.dsp.focus({ window = \"floating\" })")
      (bind "CTRL + ALT + down" "hl.dsp.focus({ window = \"tiled\" })")

      # switch workspace
      (bind "SUPER + 1" "hl.dsp.focus({ workspace = 1 })")
      (bind "SUPER + 2" "hl.dsp.focus({ workspace = 2 })")
      (bind "SUPER + 3" "hl.dsp.focus({ workspace = 3 })")
      (bind "SUPER + 4" "hl.dsp.focus({ workspace = 4 })")
      (bind "SUPER + 5" "hl.dsp.focus({ workspace = 5 })")
      (bind "SUPER + 6" "hl.dsp.focus({ workspace = 6 })")
      (bind "SUPER + 7" "hl.dsp.focus({ workspace = 7 })")
      (bind "SUPER + 8" "hl.dsp.focus({ workspace = 8 })")
      (bind "SUPER + 9" "hl.dsp.focus({ workspace = 9 })")
      (bind "SUPER + 0" "hl.dsp.focus({ workspace = 10 })")

      # same as above, but switch to the workspace
      (bind "SUPER + SHIFT + 1" "hl.dsp.window.move({ workspace = 1, silent = true })")
      (bind "SUPER + SHIFT + 2" "hl.dsp.window.move({ workspace = 2, silent = true })")
      (bind "SUPER + SHIFT + 3" "hl.dsp.window.move({ workspace = 3, silent = true })")
      (bind "SUPER + SHIFT + 4" "hl.dsp.window.move({ workspace = 4, silent = true })")
      (bind "SUPER + SHIFT + 5" "hl.dsp.window.move({ workspace = 5, silent = true })")
      (bind "SUPER + SHIFT + 6" "hl.dsp.window.move({ workspace = 6, silent = true })")
      (bind "SUPER + SHIFT + 7" "hl.dsp.window.move({ workspace = 7, silent = true })")
      (bind "SUPER + SHIFT + 8" "hl.dsp.window.move({ workspace = 8, silent = true })")
      (bind "SUPER + SHIFT + 9" "hl.dsp.window.move({ workspace = 9, silent = true })")
      (bind "SUPER + SHIFT + 0" "hl.dsp.window.move({ workspace = 10, silent = true })")
      (bind "SUPER + CTRL + c" "hl.dsp.window.move({ workspace = \"empty\" })")

      # window control
      (bind "SUPER + SHIFT + left" "hl.dsp.window.move({ direction = \"left\" })")
      (bind "SUPER + SHIFT + right" "hl.dsp.window.move({ direction = \"right\" })")
      (bind "SUPER + SHIFT + up" "hl.dsp.window.move({ direction = \"up\" })")
      (bind "SUPER + SHIFT + down" "hl.dsp.window.move({ direction = \"down\" })")
      (bind "SUPER + SHIFT + h" "hl.dsp.window.move({ direction = \"left\" })")
      (bind "SUPER + SHIFT + j" "hl.dsp.window.move({ direction = \"down\" })")
      (bind "SUPER + SHIFT + k" "hl.dsp.window.move({ direction = \"up\" })")
      (bind "SUPER + SHIFT + l" "hl.dsp.window.move({ direction = \"right\" })")

      (bind "SUPER + CTRL + left" "hl.dsp.window.resize({ x = -80, y = 0, relative = true })")
      (bind "SUPER + CTRL + right" "hl.dsp.window.resize({ x = 80, y = 0, relative = true })")
      (bind "SUPER + CTRL + up" "hl.dsp.window.resize({ x = 0, y = -80, relative = true })")
      (bind "SUPER + CTRL + down" "hl.dsp.window.resize({ x = 0, y = 80, relative = true })")
      (bind "SUPER + CTRL + h" "hl.dsp.window.resize({ x = -80, y = 0, relative = true })")
      (bind "SUPER + CTRL + j" "hl.dsp.window.resize({ x = 0, y = 80, relative = true })")
      (bind "SUPER + CTRL + k" "hl.dsp.window.resize({ x = 0, y = -80, relative = true })")
      (bind "SUPER + CTRL + l" "hl.dsp.window.resize({ x = 0, y = 80, relative = true })")

      (bind "SUPER + ALT + left" "hl.dsp.window.move({ x = -80, y = 0, relative = true })")
      (bind "SUPER + ALT + right" "hl.dsp.window.move({ x = 80, y = 0, relative = true })")
      (bind "SUPER + ALT + up" "hl.dsp.window.move({ x = 0, y = -80, relative = true })")
      (bind "SUPER + ALT + down" "hl.dsp.window.move({ x = 0, y = 80, relative = true })")
      (bind "SUPER + ALT + h" "hl.dsp.window.move({ x = -80, y = 0, relative = true })")
      (bind "SUPER + ALT + j" "hl.dsp.window.move({ x = 0, y = 80, relative = true })")
      (bind "SUPER + ALT + k" "hl.dsp.window.move({ x = 0, y = -80, relative = true })")
      (bind "SUPER + ALT + l" "hl.dsp.window.move({ x = 0, y = 80, relative = true })")

      # media and volume controls
      (bind "XF86AudioPlay" (exec "playerctl play-pause"))
      (bind "XF86AudioNext" (exec "playerctl next"))
      (bind "XF86AudioPrev" (exec "playerctl previous"))
      (bind "XF86AudioStop" (exec "playerctl stop"))

      (bind "SUPER + mouse_down" "hl.dsp.focus({ workspace = \"e-1\" })")
      (bind "SUPER + mouse_up" "hl.dsp.focus({ workspace = \"e+1\" })")

      # clipboard manager
      (bind "SUPER + V" (exec "toggle-rofi \"cliphist list | rofi -dmenu -theme-str 'window {width: 50%;} listview {columns: 1;}' | cliphist decode | wl-copy\""))

      # mouse binding (from bindm)
      (bindOpts "SUPER + mouse:272" "hl.dsp.window.drag()" { mouse = true; })
      (bindOpts "SUPER + mouse:273" "hl.dsp.window.resize()" { mouse = true; })
    ];
  };
}

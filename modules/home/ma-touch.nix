{ pkgs, ... }:
let
  ma-touch = pkgs.writers.writePython3Bin "ma-touch" {
    libraries = [ pkgs.python3Packages.pyusb ];
    flakeIgnore = [
      "E203"
      "E265"
      "E501"
      "W503"
    ];
  } (builtins.readFile ../../scripts/scripts/ma-touch.py);
  swayosd = "${pkgs.swayosd}/bin/swayosd-client";
in
{
  home.packages = [ ma-touch ];

  xdg.configFile."ma-touch/on-press.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      STATE="$HOME/.cache/asterctl/lcd-page"
      mkdir -p "$(dirname "$STATE")"
      exec 9>"$HOME/.cache/asterctl/lcd-page.lock"
      flock -n 9 || exit 0
      cur=auto
      if [[ -f "$STATE" ]]; then
        cur=$(tr -d '[:space:]' < "$STATE")
      fi
      if [[ "$cur" == 2 ]]; then
        next=1
      else
        next=2
      fi
      echo "$next" > "$STATE"
    '';
  };
  xdg.configFile."ma-touch/on-hold.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      exec ${swayosd} --output-volume mute-toggle
    '';
  };

  systemd.user.services.ma-touch = {
    Unit = {
      Description = "Microarray MAFP tap/hold → action";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${ma-touch}/bin/ma-touch";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}

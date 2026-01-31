{ ... }:
{
  systemd.user.services.documents-date-dirs = {
    Unit = {
      Description = "Ensure dated folders exist in ~/Documents and cleanup old ones";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.nix-profile/bin/documents-date-dirs";
    };
  };

  systemd.user.timers.documents-date-dirs = {
    Unit = {
      Description = "Hourly ~/Documents dated folders maintenance";
    };
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}


{ pkgs, ... }:
{
  services = {
    gvfs.enable = true;

    # GUI менеджер Bluetooth (blueman-manager), полезен для Sway/Wayland
    blueman.enable = true;

    gnome = {
      tinysparql.enable = true;
      gnome-keyring.enable = true;
    };

    dbus.enable = true;
    fstrim.enable = true;

    # needed for GNOME services outside of GNOME Desktop
    dbus.packages = with pkgs; [
      gcr
      gnome-settings-daemon
    ];

    logind.settings.Login = {
      # don’t shutdown when power button is short-pressed
      HandlePowerKey = "ignore";
    };

    udisks2.enable = true;
  };

  # Гарантируем, что Bluetooth будет включён после загрузки (Powered: yes)
  # На некоторых адаптерах powerOnBoot может не срабатывать стабильно.
  systemd.services.bluetooth-poweron = {
    description = "Force Bluetooth powered on at boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "bluetooth.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bluez}/bin/bluetoothctl power on";
    };
  };
}

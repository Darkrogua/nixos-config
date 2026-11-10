{ pkgs, ... }:
{
  # Фоновая служба для GUI AmneziaVPN (без неё — ErrorCode 103)
  programs.amnezia-vpn.enable = true;

  services = {
    gvfs.enable = true;
    fprintd.enable = true;

    # Microarray MAFP 3274:8012 — доступ пользователю (касание, не HID)
    udev.extraRules = ''
      SUBSYSTEM=="usb", ATTR{idVendor}=="3274", ATTR{idProduct}=="8012", MODE="0660", TAG+="uaccess", GROUP="users"
    '';

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
      gcr_4
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
    wants = [ "bluetooth.service" ];
    after = [ "bluetooth.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bluez}/bin/bluetoothctl --timeout 10 power on";
    };
  };

  # Сбрасываем индикаторы питания после пробуждения из сна
  # Это решает проблему с мигающей кнопкой питания после suspend/resume
  # Используем systemd-sleep hooks для срабатывания при пробуждении
  systemd.sleep.settings.Sleep = {
    AllowSuspend = true;
    AllowHibernation = false;
    AllowSuspendThenHibernate = false;
    AllowHybridSleep = false;
  };

  # Скрипт для сброса индикаторов при пробуждении
  systemd.services.reset-power-led = {
    description = "Reset power button LED after resume from suspend";
    unitConfig = {
      After = [ "sleep.target" "suspend.target" "hibernate.target" ];
      PartOf = [ "sleep.target" ];
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "reset-power-led" ''
        #!/usr/bin/env bash
        sleep 2
        for led in /sys/class/leds/*/brightness; do
          [ -f "$led" ] && echo 0 > "$led" 2>/dev/null || true
        done
        ${pkgs.systemd}/bin/udevadm trigger --action=change --subsystem-match=leds 2>/dev/null || true
      ''}";
      RemainAfterExit = true;
    };
  };

  # Хук не должен sleep'ить: systemd-sleep тогда режет его (exit 1) и тормозит resume.
  environment.etc."systemd/system-sleep/reset-power-led" = {
    mode = "0755";
    source = pkgs.writeShellScript "reset-power-led-sleep" ''
      #!/usr/bin/env bash
      case "$1" in
        post)
          (
            sleep 2
            for led in /sys/class/leds/*/brightness; do
              [ -f "$led" ] && echo 0 > "$led" 2>/dev/null || true
            done
            ${pkgs.systemd}/bin/udevadm trigger --action=change --subsystem-match=leds 2>/dev/null || true
          ) &
          ;;
      esac
      exit 0
    '';
  };
}

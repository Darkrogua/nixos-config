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

  # Сбрасываем индикаторы питания после пробуждения из сна
  # Это решает проблему с мигающей кнопкой питания после suspend/resume
  # Используем systemd-sleep hooks для срабатывания при пробуждении
  systemd.sleep.extraConfig = ''
    [Sleep]
    AllowSuspend=yes
    AllowHibernation=no
    AllowSuspendThenHibernate=no
    AllowHybridSleep=no
  '';

  # Скрипт для сброса индикаторов при пробуждении
  # Используем более надежный подход через systemd-sleep hook
  systemd.services.reset-power-led = {
    description = "Reset power button LED after resume from suspend";
    unitConfig = {
      # Запускаем после пробуждения
      After = [ "sleep.target" "suspend.target" "hibernate.target" ];
      # Запускаем при деактивации sleep.target (т.е. при пробуждении)
      PartOf = [ "sleep.target" ];
    };
    serviceConfig = {
      Type = "oneshot";
      # Пробуем разные способы сброса индикаторов питания
      ExecStart = "${pkgs.writeShellScript "reset-power-led" ''
        #!/usr/bin/env bash
        # Ждем немного после пробуждения
        sleep 2
        
        # Сбрасываем все LED индикаторы
        for led in /sys/class/leds/*/brightness; do
          [ -f "$led" ] && echo 0 > "$led" 2>/dev/null || true
        done
        
        # Пробуем через udevadm для сброса состояния устройств
        ${pkgs.systemd}/bin/udevadm trigger --action=change --subsystem-match=leds 2>/dev/null || true
        
        # Пробуем сбросить состояние через systemctl
        ${pkgs.systemd}/bin/systemctl reset-failed sleep.target 2>/dev/null || true
      ''}";
      RemainAfterExit = true;
    };
  };

  # Также создаем systemd-sleep скрипт для более надежного срабатывания
  # Этот скрипт выполняется напрямую при пробуждении (более надежный способ)
  systemd.tmpfiles.rules = [
    "f /etc/systemd/system-sleep/reset-power-led 0755 root root - ${pkgs.writeShellScript "reset-power-led" ''
      #!/usr/bin/env bash
      case "$1" in
        post)
          # После пробуждения - сбрасываем индикаторы и состояние
          sleep 2
          
          # Сбрасываем все LED индикаторы
          for led in /sys/class/leds/*/brightness; do
            [ -f "$led" ] && echo 0 > "$led" 2>/dev/null || true
          done
          
          # Пробуем сбросить через udevadm
          ${pkgs.systemd}/bin/udevadm trigger --action=change --subsystem-match=leds 2>/dev/null || true
          
          # Пробуем сбросить состояние кнопки питания через systemctl
          ${pkgs.systemd}/bin/systemctl reset-failed sleep.target 2>/dev/null || true
          
          # Пробуем перезагрузить systemd-logind для сброса состояния
          ${pkgs.systemd}/bin/systemctl reload systemd-logind.service 2>/dev/null || true
          
          # Пробуем через acpi_call (если доступно) для сброса состояния кнопки питания
          if [ -f /proc/acpi/call ]; then
            echo '\\_SB.PCI0.LPC0.EC0.PBTS' > /proc/acpi/call 2>/dev/null || true
          fi
          ;;
      esac
    ''}"
  ];
}

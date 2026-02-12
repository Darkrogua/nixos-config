{ pkgs, username, ... }:
{
  # Копируем бинарники в системные пути
  systemd.tmpfiles.rules = [
    "L+ /usr/local/bin/asterctl - - - - /home/${username}/Soft/aoostar-display/asterctl"
    "L+ /usr/local/bin/aster-sysinfo - - - - /home/${username}/Soft/aoostar-display/aster-sysinfo"
  ];

  # Сервис для сбора информации о системе (aster-sysinfo)
  # Этот демон собирает данные о системе для отображения на встроенном LCD экране
  systemd.services.aster-sysinfo = {
    description = "Daemon for gathering sensor values for asterctl";
    wantedBy = [ "multi-user.target" ];
    before = [ "asterctl-panel.service" ];
    after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
    requires = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "exec";
      User = "${username}";
      # Создаем директорию для сенсоров в домашней директории
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /home/${username}/.cache/asterctl/sensors";
      # Используем прямой путь к бинарнику
      # Пишем данные в домашнюю директорию, чтобы избежать проблем с правами доступа
      ExecStart = "/home/${username}/Soft/aoostar-display/aster-sysinfo --out /home/${username}/.cache/asterctl/sensors/sysinfo.txt --temp-dir /home/${username}/.cache/asterctl --refresh 3";
      UMask = "002";
      # Безопасность: ограничиваем доступ сервиса
      CapabilityBoundingSet = "";
      LockPersonality = true;
      RestrictNamespaces = true;
      ProtectHome = false;  # Нужен доступ к домашней директории для запуска бинарников
      ProtectSystem = "strict";
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      MemoryDenyWriteExecute = false;  # Нужно для выполнения бинарников из домашней директории
      RestrictSUIDSGID = true;
      KeyringMode = "private";
      ProtectClock = true;
      RestrictRealtime = true;
      PrivateTmp = true;
      PrivateUsers = true;
      ProtectHostname = true;
      RestrictAddressFamilies = "none";
      SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
      SystemCallErrorNumber = "EPERM";
    };
  };

  # Сервис для отображения панелей с информацией о системе на встроенном LCD экране
  systemd.services.asterctl-panel = {
    description = "Display sensor panels on AOOSTAR embedded LCD";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" "systemd-tmpfiles-setup.service" "aster-sysinfo.service" ];
    requires = [ "aster-sysinfo.service" ];
    serviceConfig = {
      Type = "simple";
      User = "${username}";
      Group = "dialout";
      WorkingDirectory = "/home/${username}/Soft/aoostar-display";
      # Создаем директорию и преобразуем данные от aster-sysinfo в формат, ожидаемый конфигурацией перед запуском
      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p /home/${username}/.cache/asterctl/sensors"
        "${pkgs.bash}/bin/bash /home/${username}/Soft/aoostar-display/convert-sensors.sh"
      ];
      # Запускаем asterctl в режиме sensor panel
      # --config указывает на файл конфигурации панелей
      # --sensor-path указывает на файл с преобразованными данными в домашней директории
      # --config-dir указывает на директорию с конфигурацией
      ExecStart = "${pkgs.bash}/bin/bash -c 'exec /home/${username}/Soft/aoostar-display/asterctl --config monitor.json --config-dir /home/${username}/Soft/aoostar-display/cfg --sensor-path /home/${username}/.cache/asterctl/sensors/values.txt'";
      Restart = "always";
      RestartSec = "5";
      # Безопасность: ограничиваем доступ сервиса
      CapabilityBoundingSet = "";
      LockPersonality = true;
      RestrictNamespaces = true;
      ProtectHome = false;  # Нужен доступ к домашней директории для конфигурации
      ProtectSystem = "strict";
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      MemoryDenyWriteExecute = false;  # Нужно для выполнения бинарников из домашней директории
      RestrictSUIDSGID = true;
      KeyringMode = "private";
      ProtectClock = true;
      RestrictRealtime = true;
      PrivateTmp = true;
      PrivateUsers = true;
      ProtectHostname = true;
      RestrictAddressFamilies = "none";
      SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
      SystemCallErrorNumber = "EPERM";
      # Доступ к /dev/ttyACM0 и /dev/ttyACM1 — номер зависит от порядка USB-подключений
      DeviceAllow = [ "/dev/ttyACM0 rw" "/dev/ttyACM1 rw" ];
    };
  };

  # Timer для периодического обновления преобразованных данных сенсоров
  # Обновляем данные каждые 3 секунды (как часто aster-sysinfo обновляет данные)
  systemd.timers.asterctl-sensor-convert = {
    description = "Convert sensor data for asterctl panels";
    wantedBy = [ "timers.target" ];
    after = [ "aster-sysinfo.service" ];
    timerConfig = {
      OnActiveSec = "3s";
      OnUnitActiveSec = "3s";
      AccuracySec = "1s";
    };
  };

  systemd.services.asterctl-sensor-convert = {
    description = "Convert sensor data format for asterctl";
    serviceConfig = {
      Type = "oneshot";
      User = "${username}";
      # Используем RuntimeDirectory для чтения данных от aster-sysinfo
      RuntimeDirectory = "asterctl";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /home/${username}/.cache/asterctl/sensors";
      ExecStart = "${pkgs.bash}/bin/bash /home/${username}/Soft/aoostar-display/convert-sensors.sh";
      # Безопасность
      ProtectHome = false;  # Нужен доступ к домашней директории для записи
      ProtectSystem = "strict";
      NoNewPrivileges = true;
      MemoryDenyWriteExecute = false;
    };
  };
}

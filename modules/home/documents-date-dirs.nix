# Поддержка папок с датами в ~/Documents: создание папки на сегодня (ДД.ММ.ГГ)
# и очистка старых/пустых. Запуск при входе (systemd + exec-once) и раз в час (таймер).
{ pkgs, ... }:
let
  script = pkgs.writeScriptBin "documents-date-dirs" (
    builtins.readFile ../../scripts/scripts/documents-date-dirs.sh
  );
in
{
  # Сервис: один запуск скрипта (oneshot). Запускается при старте сессии и по таймеру.
  systemd.user.services.documents-date-dirs = {
    Unit = {
      Description = "Папки с датами в ~/Documents: создать сегодняшнюю, удалить старые/пустые";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${script}/bin/documents-date-dirs";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Таймер: раз в час запускает тот же сервис. Persistent = после пропуска (ПК был выключен) догоняет.
  systemd.user.timers.documents-date-dirs = {
    Unit = {
      Description = "Раз в час: обслуживание папок с датами в ~/Documents";
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


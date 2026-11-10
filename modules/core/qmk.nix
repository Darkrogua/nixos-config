{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    via
    vial
    qmk
    qmk-udev-rules
  ];

  # 50-qmk.rules ставит GROUP="plugdev"; без группы udev орёт на каждое USB-событие
  users.groups.plugdev = { };

  services.udev.packages = with pkgs; [
    via
    vial
    qmk-udev-rules
  ];
}

{ pkgs, ... }:
{
  # imports = [ inputs.nix-gaming.nixosModules.default ];
  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # substituters подменяет дефолт целиком — без cache.nixos.org всё шло только в Cachix и
      # зависало на недоступных зеркалах. extra-* дополняет стандартный кэш.
      extra-substituters = [
        "https://nix-community.cachix.org"
        "https://nix-gaming.cachix.org"
        "https://hyprland.cachix.org"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
      connect-timeout = 10;
    };
  };

  # Android Debug Bridge (adb) для отладки/прошивки с устройств.
  # В текущей версии NixOS опция `programs.adb` может быть бесполезной,
  # поэтому просто ставим пакет с `adb`.

  environment.systemPackages = with pkgs; [
    android-tools # adb/fastboot
    wget
    git
    ranger
    usbutils
    libinput
    fprintd
  ];

  time.timeZone = "Europe/Saratov";
  i18n.defaultLocale = "ru_RU.UTF-8";
  # Явно генерируем нужные локали (на случай если ru_RU не был доступен в окружении раньше)
  i18n.supportedLocales = [
    "ru_RU.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];
  # Чтобы даты/дни недели были по-русски, но при желании можно оставить остальные категории en_US
  i18n.extraLocaleSettings = {
    LC_TIME = "ru_RU.UTF-8";
  };

  # Важно для waybar clock.locale (и некоторых других GUI программ): чтобы glibc находил архив локалей на NixOS
  environment.sessionVariables.LOCALE_ARCHIVE = "/run/current-system/sw/lib/locale/locale-archive";

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
}

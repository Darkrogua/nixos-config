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
      substituters = [
        "https://nix-community.cachix.org"
        "https://nix-gaming.cachix.org"
        "https://hyprland.cachix.org"
        "https://ghostty.cachix.org"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "ghostty.cachix.org-1:QB389yTa6gTyneehvqG58y0WnHjQOqgnA+wBnpWWxns="
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    wget
    git
    ranger
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

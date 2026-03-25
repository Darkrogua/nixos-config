{ ... }:
{
  security = {
    rtkit.enable = true;
    sudo.enable = true;

    pam.services = {
      swaylock.fprintAuth = true;
      hyprlock.fprintAuth = true;
    };
  };
}

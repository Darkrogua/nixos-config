{ ... }:
{
  security = {
    polkit.enable = true;
    rtkit.enable = true;
    sudo.enable = true;

    pam.services = {
      swaylock.fprintAuth = false;
      hyprlock.fprintAuth = false;
    };
  };
}

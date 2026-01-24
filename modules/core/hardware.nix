{ pkgs, ... }:
{
  hardware = {
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        (intel-vaapi-driver.override { enableHybridCodec = true; })
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };

    # Bluetooth (для Sway/Waybar и управления гарнитурами/девайсами)
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };
  hardware.enableRedistributableFirmware = true;
}

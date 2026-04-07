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
        # OpenCL ICD для hashcat (CL_PLATFORM_NOT_FOUND_KHR без него).
        # На AMD без ROCm — OpenCL на CPU; GPU-ускорение — отдельно через ROCm.
        pocl
        # AMD ROCm OpenCL ICD (важно: именно `.icd`).
        rocmPackages.clr.icd
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

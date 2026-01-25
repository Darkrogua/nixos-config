{ pkgs, username, ... }:
{
  # Add user to libvirtd and docker groups
  users.users.${username}.extraGroups = [ "libvirtd" "docker" ];

  # Install necessary packages
  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    spice
    spice-gtk
    spice-protocol
    virtio-win
    win-spice
    adwaita-icon-theme
    docker-compose
  ];

  # Manage the virtualisation services
  virtualisation = {
    docker = {
      enable = true;
      daemon.settings = {
        data-root = "/var/lib/docker";
      };
    };
    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
      };
    };
    spiceUSBRedirection.enable = true;
  };
  services.spice-vdagentd.enable = true;
}

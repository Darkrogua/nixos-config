{ pkgs, host, ... }:
{
  networking = {
    hostName = "${host}";
    networkmanager.enable = true;
    nameservers = [
      "8.8.8.8"
      "8.8.4.4"
      "1.1.1.1"
    ];
    
    # Добавление записей в /etc/hosts
    hosts = {
      "127.0.0.1" = [ "localhost" "adminer.dc" "ktng.dc" "babylon.dc" "faces.dc" "tbot.dc" ];
      "::1" = [ "localhost" ];
    };
    
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        80
        443
        59010
        59011
      ];
      allowedUDPPorts = [
        59010
        59011
      ];
    };
  };

  environment.systemPackages = with pkgs; [ networkmanagerapplet ];
}

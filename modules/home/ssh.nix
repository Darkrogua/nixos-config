{ ... }:
{
  programs.ssh = {
    enable = true;

    enableDefaultConfig = false;

    # RFC 42: settings вместо deprecated matchBlocks
    settings = {
      "*" = {
        AddKeysToAgent = "1h";

        ControlMaster = "auto";
        ControlPath = "~/.ssh/control-%r@%h:%p";
        ControlPersist = "10m";

        ForwardAgent = false;
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
      };

      "bitbucket.org" = {
        IdentityFile = "~/.ssh/keys/bitbucket.org/id_rsa";
        IdentitiesOnly = true;
      };

      "github.com" = {
        IdentityFile = "~/.ssh/keys/github.com/id_ed25519";
        IdentitiesOnly = true;
      };

      "gitlab.com" = {
        IdentityFile = "~/.ssh/keys/gitlab.com/id_rsa";
        IdentitiesOnly = true;
      };

      "gcorelabs.com" = {
        IdentityFile = "~/.ssh/keys/gcorelabs.com/id_rsa";
        IdentitiesOnly = true;
      };

      "79.133.122.242" = {
        IdentityFile = "~/.ssh/keys/79.133.122.242/id_rsa";
        IdentitiesOnly = true;
      };

      "89.223.91.78" = {
        IdentityFile = "~/.ssh/keys/89.223.91.78/id_rsa";
        IdentitiesOnly = true;
      };

      "192.168.2.1" = {
        IdentityFile = "~/.ssh/keys/192.168.2.1/id_ed25519";
        IdentitiesOnly = true;
      };

      "192.168.2.89" = {
        IdentityFile = "~/.ssh/keys/hdocker/id_ed25519";
        IdentitiesOnly = true;
      };

      "192.168.2.79" = {
        IdentityFile = "~/.ssh/keys/hnextcloud/id_ed25519";
        IdentitiesOnly = true;
      };

      "192.168.100.5" = {
        IdentityFile = "~/.ssh/keys/wifi-ubuntu/id_ed25519";
        IdentitiesOnly = true;
      };

      "192.168.100.171" = {
        IdentityFile = "~/.ssh/keys/192.168.100.171/id_ed25519";
        IdentitiesOnly = true;
      };

      "gitlab.nopreset.net" = {
        IdentityFile = "~/.ssh/keys/gitlab.nopreset.net/id_ed25519";
        IdentitiesOnly = true;
      };

      "mcmrakk.myjino.ru" = {
        IdentityFile = "~/.ssh/keys/mcmraak.myjino.ru/id_rsa";
        IdentitiesOnly = true;
      };

      "gitlab.awg.ru" = {
        IdentityFile = "~/.ssh/keys/gitlab.awg.ru/gitlabawg";
        IdentitiesOnly = true;
      };

      "bauer-inua.com" = {
        IdentityFile = "~/.ssh/keys/bauer-inua.com/id_ed25519";
        IdentitiesOnly = true;
      };
    };
  };

  services.ssh-agent.enable = true;
}

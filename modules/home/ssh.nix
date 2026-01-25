{ ... }:
{
  programs.ssh = {
    enable = true;

    enableDefaultConfig = false;

    matchBlocks = {
      "*" = {
        addKeysToAgent = "1h";

        controlMaster = "auto";
        controlPath = "~/.ssh/control-%r@%h:%p";
        controlPersist = "10m";

        forwardAgent = false;
        compression = false;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
      };

      bitbucket = {
        host = "bitbucket.org";
        identityFile = "~/.ssh/keys/bitbucket.org/id_rsa";
        identitiesOnly = true;
      };

      github = {
        host = "github.com";
        identityFile = "~/.ssh/keys/github.com/id_ed25519";
        identitiesOnly = true;
      };

      gitlab = {
        host = "gitlab.com";
        identityFile = "~/.ssh/keys/gitlab.com/id_rsa";
        identitiesOnly = true;
      };

      gcorelabs = {
        host = "gcorelabs.com";
        identityFile = "~/.ssh/keys/gcorelabs.com/id_rsa";
        identitiesOnly = true;
      };

      "79.133.122.242" = {
        host = "79.133.122.242";
        identityFile = "~/.ssh/keys/79.133.122.242/id_rsa";
        identitiesOnly = true;
      };

      "89.223.91.78" = {
        host = "89.223.91.78";
        identityFile = "~/.ssh/keys/89.223.91.78/id_rsa";
        identitiesOnly = true;
      };

      "192.168.2.1" = {
        host = "192.168.2.1";
        identityFile = "~/.ssh/keys/192.168.2.1/id_ed25519";
        identitiesOnly = true;
      };

      "192.168.2.89" = {
        host = "192.168.2.89";
        identityFile = "~/.ssh/keys/hdocker/id_ed25519";
        identitiesOnly = true;
      };

      "192.168.2.79" = {
        host = "192.168.2.79";
        identityFile = "~/.ssh/keys/hnextcloud/id_ed25519";
        identitiesOnly = true;
      };

      "192.168.100.5" = {
        host = "192.168.100.5";
        identityFile = "~/.ssh/keys/wifi-ubuntu/id_ed25519";
        identitiesOnly = true;
      };

      "gitlab.nopreset.net" = {
        host = "gitlab.nopreset.net";
        identityFile = "~/.ssh/keys/gitlab.nopreset.net/id_ed25519";
        identitiesOnly = true;
      };

      "mcmrakk.myjino.ru" = {
        host = "mcmrakk.myjino.ru";
        identityFile = "~/.ssh/keys/mcmraak.myjino.ru/id_rsa";
        identitiesOnly = true;
      };

      "gitlab.awg.ru" = {
        host = "gitlab.awg.ru";
        identityFile = "~/.ssh/keys/gitlab.awg.ru/gitlabawg";
        identitiesOnly = true;
      };

      "bauer-inua.com" = {
        host = "bauer-inua.com";
        identityFile = "~/.ssh/keys/bauer-inua.com/id_ed25519";
        identitiesOnly = true;
      };
    };
  };

  services.ssh-agent.enable = true;
}

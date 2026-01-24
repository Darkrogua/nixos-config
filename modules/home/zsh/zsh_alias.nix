{ ... }:
{
  programs.zsh = {
    shellAliases = {
      # Utils
      c = "clear";
      cd = "z";
      tt = "gtrash put";
      cat = "bat";
      nano = "micro";
      code = "codium";
      diff = "delta --diff-so-fancy --side-by-side";
      less = "bat";
      copy = "wl-copy";
      f = "superfile";
      py = "python";
      ipy = "ipython";
      icat = "kitten icat";
      dsize = "du -hs";
      pdf = "tdf";
      open = "xdg-open";
      space = "ncdu";
      man = "batman";

      l = "eza --icons -a --group-directories-first -1 --no-user --long"; # EZA_ICON_SPACING=2
      tree = "eza --icons --tree --group-directories-first";

      # Nixos
      cdnix = "cd ~/nixos-config && codium ~/nixos-config";
      ns = "nom-shell --run zsh";
      nd = "nom develop --command zsh";
      nb = "nom build";
      nc = "nh-notify nh clean all --keep 5";
      nft = "nh-notify nh os test";
      nfs = "nh-notify nh os switch";
      nfu = "nh-notify nh os switch --update";
      nsearch = "nh search";
      # Ребилд без cd (прямо из любой директории)
      # NB: для flake из git-репо новые/удалённые НЕотслеживаемые файлы не попадают в source без --impure
      nsw = "sudo nixos-rebuild switch --flake ~/nixos-config#laptop --impure";

      # python
      piv = "python -m venv .venv";
      psv = "source .venv/bin/activate";

      # SSD Benchmark (fio)
      ssd-test = "fio --name=ssd-test --filename=/tmp/fio-test --size=1G --direct=1 --rw=readwrite --bs=1M --ioengine=libaio --iodepth=32 --runtime=30 --time_based --group_reporting";
      ssd-read = "fio --name=ssd-read --filename=/tmp/fio-test --size=1G --direct=1 --rw=read --bs=1M --ioengine=libaio --iodepth=32 --runtime=30 --time_based --group_reporting";
      ssd-write = "fio --name=ssd-write --filename=/tmp/fio-test --size=1G --direct=1 --rw=write --bs=1M --ioengine=libaio --iodepth=32 --runtime=30 --time_based --group_reporting";
      ssd-randread = "fio --name=ssd-randread --filename=/tmp/fio-test --size=1G --direct=1 --rw=randread --bs=4k --ioengine=libaio --iodepth=32 --runtime=30 --time_based --group_reporting";
      ssd-randwrite = "fio --name=ssd-randwrite --filename=/tmp/fio-test --size=1G --direct=1 --rw=randwrite --bs=4k --ioengine=libaio --iodepth=32 --runtime=30 --time_based --group_reporting";
      ssd-full = "fio --name=ssd-full --filename=/tmp/fio-test --size=1G --direct=1 --rw=readwrite --bs=1M --ioengine=libaio --iodepth=32 --runtime=60 --time_based --group_reporting && fio --name=ssd-rand --filename=/tmp/fio-test --size=1G --direct=1 --rw=randrw --bs=4k --ioengine=libaio --iodepth=32 --runtime=60 --time_based --group_reporting";
    };
  };
}

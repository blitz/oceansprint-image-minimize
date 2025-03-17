{ config, pkgs, ... }: {

  zramSwap = {
    # TODO zram-generator fails to compile for ARM.
    enable = true;

    algorithm = "zstd";
    memoryPercent = 20;
  };

  boot.initrd = {
    systemd.services.populate-init-nix-store = {
      description = "Preserve the /nix/store from the initramfs";
      wantedBy = [ "initrd.target" ];
      before = [ "initrd.target" ];
      unitConfig = {
        DefaultDependencies = false;
        RequiresMountsFor = "/run/initrd-nix-store";
      };

      serviceConfig.Type = "oneshot";

      script = ''
        cp -a /nix/store /run/initrd-nix-store

        # Make everything read-only.
        # TODO: This could be nicer if it's a different tmpfs that we can remount read-only.
        chmod -R a-w /run/initrd-nix-store
      '';
    };

  };

  fileSystems = {
    "/" = {
      fsType = "tmpfs";
      options = [
        "size=20%"
      ];
    };

    "/var" =
      let
        partConf = config.image.repart.partitions."var".repartConfig;
      in
      {
        device = "/dev/disk/by-partuuid/${partConf.UUID}";
        fsType = partConf.Format;
      };

    "/boot" =
      let
        partConf = config.image.repart.partitions."esp".repartConfig;
      in
      {
        device = "/dev/disk/by-partuuid/${partConf.UUID}";
        fsType = partConf.Format;
      };

    "/nix/store-base" =
      let
        partConf = config.image.repart.partitions."store".repartConfig;
      in
      {
        device = "/dev/disk/by-partlabel/${partConf.Label}";
        fsType = partConf.Format;

        # Otherwise mounting /nix/store fails below.
        neededForBoot = true;
      };

    "/nix/store".overlay = {
      lowerdir = [
        "/run/initrd-nix-store"
        "/nix/store-base"
      ];
    };
  };
}

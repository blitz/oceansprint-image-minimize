{ config, pkgs, lib, modulesPath, ... }: {

  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  image.repart =
    let
      efiArch = pkgs.stdenv.hostPlatform.efiArch;

      makeClosure = paths: pkgs.closureInfo { rootPaths = paths; };

      storePaths = toplevel: "${pkgs.closureInfo { rootPaths = [ toplevel ]; }}/store-paths";

      initrdStoreFiles = initrd: pkgs.runCommand "initrd-paths" {
        nativeBuildInputs = [ pkgs.libarchive ];
      } ''
        bsdtar tf "${initrd}/initrd" | grep '^nix/store/' | sed s,^nix/store/,, > $out
      '';

      storeContent = { toplevel, initrd }: pkgs.runCommand "store-content" {
        # The store image is self-contained.
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      } ''
        mkdir -p $out
        for p in $(cat ${storePaths toplevel}); do
          cp -va "$p" $out
        done

        # OTherwise, we can't delete files below.
        chmod -R u+w $out/

        directories=()
        for p in $(cat ${initrdStoreFiles initrd}); do
          if [ -f "$out/$p" ]; then
            rm -v "$out/$p"
          else
            directories+=("$out/$p")
          fi
        done

        for d in "''${directories[@]}"; do
          # Directories may not be empty.
          rmdir -v "$d" || true
        done

        chmod -R u-w $out/
      '';
    in
    {
      name = config.boot.uki.name;
      split = true;

      partitions = {
        "esp" = {
          contents = {
            "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
              "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

            "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
              "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";

            # systemd-boot configuration
            "/loader/loader.conf".source = (pkgs.writeText "$out" ''
              timeout 3
            '');
          };
          repartConfig = {
            Type = "esp";
            UUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"; # Well known
            Format = "vfat";
            SizeMinBytes = "256M";
            SplitName = "-";
          };
        };

        # TODO: We should create this at boot time and not bake it into the image.
        "swap" = {
          repartConfig = {
            Type = "swap";
            SizeMinBytes = "512M";
            SizeMaxBytes = "512M";
          };
        };

        "store" = {
          contents."/".source = "${storeContent {
            toplevel = config.system.build.toplevel;
            initrd = config.system.build.initialRamdisk;
          }}";

          repartConfig = {
            Type = "linux-generic";
            Label = "store_${config.system.image.version}";
            Format = "squashfs";
            Minimize = "off";
            ReadOnly = "yes";

            SizeMinBytes = "1G";
            SizeMaxBytes = "1G";
            SplitName = "store";
          };
        };

        # Placeholder for the second installed Nix store.
        # TODO: We should create this at boot time and not bake it into the image.
        "store-empty" = {
          repartConfig = {
            Type = "linux-generic";
            Label = "_empty";
            Minimize = "off";
            SizeMinBytes = "1G";
            SizeMaxBytes = "1G";
            SplitName = "-";
          };
        };

        # Persistent storage
        "var" = {
          repartConfig = {
            Type = "var";
            UUID = "4d21b016-b534-45c2-a9fb-5c16e091fd2d"; # Well known
            Format = "ext4";
            Label = "nixos-persistent";
            Minimize = "off";

            # Has to be large enough to hold update files.
            SizeMinBytes = "2G";
            SizeMaxBytes = "2G";
            SplitName = "-";

            # Wiping this gives us a clean state.
            FactoryReset = "yes";
          };
        };
      };
    };
}

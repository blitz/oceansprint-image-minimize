{
  description = "systemd-sysupdate / systemd-repart Example";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      inherit (nixpkgs) lib;

      # The platform we want to build on. This should ideally be configurable.
      buildPlatform = "x86_64-linux";

      # We use this to build derivations for the build platform.
      buildPkgs = nixpkgs.legacyPackages."${buildPlatform}";
    in
    (flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        # We use this later to add some extra outputs for the build system.
        isBuildPlatform = system == buildPlatform;

        # We treat everything as cross-compilation without a special
        # case for isBuildSystem. Nixpkgs will do the right thing.
        crossPkgs = import nixpkgs { localSystem = buildPlatform; crossSystem = system; };

        # A convenience wrapper around lib.nixosSystem that configures
        # cross-compilation.
        crossNixos = module: lib.nixosSystem {
          modules = [
            module

            {
              # We could also use these to trigger cross-compilation,
              # but we already have the ready-to-go crossPkgs.
              #
              # nixpkgs.buildPlatform = buildSystem;
              # nixpkgs.hostPlatform = system;
              nixpkgs.pkgs = crossPkgs;
            }
          ];
        };
      in
      # Some outputs only make sense for the build system, e.g. the development shell.
      (lib.optionalAttrs isBuildPlatform (import ./buildHost.nix { pkgs = buildPkgs; }))
      //
      {
        packages =
          let
            appliance_18 = crossNixos {
              imports = [
                ./base.nix
                ./version-18.nix

                {
                  boot.kernel.externalBootloader = true;
                }
              ];

              system.image.version = "18";
            };
          in
          {
            default = self.packages."${system}".appliance_18_image;

            config = appliance_18.config;
            kernel = appliance_18.config.boot.kernelPackages.kernel;
            uki = appliance_18.config.system.build.uki;
            initrd = appliance_18.config.system.build.initialRamdisk;
            toplevel = appliance_18.config.system.build.toplevel;
            image = self.lib.mkInstallImage appliance_18;
          };
      })) // {
      lib = {
        # Prepare a ready-to-boot disk image.
        mkInstallImage = nixos:
          let
            config = nixos.config;
          in
          buildPkgs.runCommand "image-${config.system.image.version}"
            {
              nativeBuildInputs = with buildPkgs; [ qemu ];
            } ''
            mkdir -p $out
            qemu-img convert -f raw -O qcow2 \
              -C ${config.system.build.image}/${config.boot.uki.name}_${config.system.image.version}.raw \
              $out/disk.qcow2
          '';
      };
    };
}

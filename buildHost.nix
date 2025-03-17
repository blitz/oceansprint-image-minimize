{ pkgs }:
let
  # A helper script to run the disk images above.
  qemu-efi = pkgs.writeShellApplication {
    name = "qemu-efi";

    runtimeInputs = [ pkgs.qemu ];

    text = ''
      if [ $# -lt 2 ]; then
        echo "Usage: qemu-efi ARCH disk-image [qemu-args...]" >&2
        exit 1
      fi

      ARCH="$1"
      DISK="$2"
      shift; shift


      case "$ARCH" in
           x86_64)
              qemu-system-x86_64 \
                -smp 2 -m 2048 -machine q35,accel=kvm \
                -bios "${pkgs.OVMF.fd}/FV/OVMF.fd" \
                -snapshot \
                -serial stdio -hda "$DISK" "$@"
              ;;
           *)
              echo "Unknown architecture: $ARCH" >&2
              exit 1
              ;;
      esac
    '';
  };
in
{
  devShells.default = pkgs.mkShell {
    packages = [
      qemu-efi
    ];
  };

  packages = {
    inherit qemu-efi;
  };
}

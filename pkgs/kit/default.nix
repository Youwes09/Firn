# The installer kit for a NixOS configuration. Built with the build machine's
# own tools (it only copies and archives data), so on an x86_64 host only the
# aarch64 system itself needs emulation.
{
  callPackage,
  runCommand,
  python3,
  # The aarch64 NixOS configuration (nixpkgs.lib.nixosSystem result).
  nixos,
  # pkgs/installer.
  installer,
}:
let
  cfg = nixos.config;
  toplevel = cfg.system.build.toplevel;

  rootImage = callPackage "${toString nixos.pkgs.path}/nixos/lib/make-ext4-fs.nix" {
    storePaths = [ toplevel ];
    volumeLabel = cfg.hardware.firn.image.label;
    uuid = cfg.hardware.firn.image.rootUuid;
  };
in
runCommand "firn-kit-${cfg.system.nixos.label}"
  {
    nativeBuildInputs = [ python3 ];
    passthru = { inherit rootImage toplevel; };
  }
  ''
    # The installer needs a whole number of MiB; the filesystem may be smaller.
    cp ${rootImage} root.ext4
    chmod u+w root.ext4
    size=$(stat -c %s root.ext4)
    truncate -s $(( (size + 1048575) / 1048576 * 1048576 )) root.ext4

    python3 -I ${./make-kit.py} \
      --installer ${installer} \
      --installer-src ${installer.src} \
      --firn-boot ${../firn-boot/firn-boot.py} \
      --root-image root.ext4 \
      --loader ${toplevel}/m1n1.bin \
      --kernel ${toplevel}/kernel \
      --dtb ${toplevel}/dtbs/apple/t8132-j713.dtb \
      --initrd ${toplevel}/initrd \
      --kernel-params ${toplevel}/kernel-params \
      --init ${toplevel}/init \
      --os-name Firn \
      --install-command ${./Install.command} \
      --preflight ${./preflight.command} \
      --start-here ${./START-HERE.md} \
      --guide ${../../docs/GUIDE.md} \
      --out $out
  ''

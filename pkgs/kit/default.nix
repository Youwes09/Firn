# The installer kit for a NixOS configuration. Built with the build machine's
# own tools (it only copies and archives data), so on an x86_64 host only the
# aarch64 system itself needs emulation.
{
  callPackage,
  runCommand,
  python3,
  # The aarch64 NixOS configuration (nixpkgs.lib.nixosSystem result).
  nixos,
}:
let
  sources = callPackage ../sources.nix { };
  cfg = nixos.config;
  toplevel = cfg.system.build.toplevel;

  rootImage = callPackage "${toString nixos.pkgs.path}/nixos/lib/make-ext4-fs.nix" {
    storePaths = [ toplevel ];
    volumeLabel = cfg.hardware.m4-j713.image.label;
    uuid = cfg.hardware.m4-j713.image.rootUuid;
  };
in
runCommand "m4-nix-kit-${cfg.system.nixos.label}"
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
      --installer-kit ${sources.installerKit} \
      --root-image root.ext4 \
      --loader ${sources.loader} \
      --kernel ${toplevel}/kernel \
      --dtb ${toplevel}/dtbs/apple/m4-nix-j713.dtb \
      --initrd ${toplevel}/initrd \
      --kernel-params ${toplevel}/kernel-params \
      --init ${toplevel}/init \
      --rootfs-uuid ${cfg.hardware.m4-j713.image.rootUuid} \
      --os-name NixOS \
      --nix-boot ${../m4-nix-boot/m4-nix-boot.py} \
      --install-command ${./Install.command} \
      --preflight ${./preflight.command} \
      --start-here ${./START-HERE.md} \
      --guide ${../../docs/GUIDE.md} \
      --out $out
  ''

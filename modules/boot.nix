# Booting through m1n1: every generation is written into <ESP>/m1n1/boot.bin
# by firn-boot, with its own m1n1 stage 2, kernel, devicetree and initrd.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.firn;
  firn-boot = pkgs.callPackage ../pkgs/firn-boot { };
  # Cross-compiled on cfg.buildSystem, like the kernel.
  m1n1 =
    (import pkgs.path {
      localSystem = cfg.buildSystem;
      crossSystem = pkgs.stdenv.hostPlatform.system;
    }).callPackage
      ../pkgs/m1n1
      { };
in
{
  config = lib.mkIf cfg.enable {
    # firn-boot reads <toplevel>/dtbs/apple/t8132-j713.dtb.
    hardware.deviceTree = {
      enable = true;
      filter = "t8132-j713.dtb";
    };

    # firn-boot writes <toplevel>/m1n1.bin into boot.bin.
    system.systemBuilderCommands = ''
      ln -s ${m1n1}/lib/m1n1/m1n1.bin $out/m1n1.bin
    '';

    boot.initrd.systemd.enable = true;
    # The installer and firn-boot both require one gzip initrd.
    boot.initrd.compressor = "gzip";

    environment.systemPackages = [
      firn-boot
      (pkgs.callPackage ../pkgs/firn-report { })
    ];

    # The installer creates the EFI system partition and m1n1 stage 1 passes its
    # partition UUID in the devicetree, so it is found at boot, not in fstab.
    systemd.services.firn-esp = {
      description = "Mount the EFI system partition named by m1n1";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      path = [
        pkgs.coreutils
        pkgs.util-linux
        config.systemd.package
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mountpoint -q ${lib.escapeShellArg cfg.efiMountPoint} && exit 0
        uuid=$(tr -d '\0' < '/proc/device-tree/chosen/asahi,efi-system-partition')
        case "$uuid" in
          ????????-????-????-????-????????????) ;;
          *) echo "m1n1 named no valid EFI partition: '$uuid'" >&2; exit 1 ;;
        esac
        device=/dev/disk/by-partuuid/''${uuid,,}
        udevadm wait --timeout=30 "$device"
        mkdir -p ${lib.escapeShellArg cfg.efiMountPoint}
        mount -t vfat -o umask=0077,nodev,nosuid,noexec "$device" ${lib.escapeShellArg cfg.efiMountPoint}
      '';
    };

    boot.loader.grub.enable = false;
    boot.loader.external = {
      enable = true;
      installHook = pkgs.writeShellScript "firn-boot-install" ''
        set -e
        if ! ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg cfg.efiMountPoint}; then
          ${config.systemd.package}/bin/systemctl start firn-esp.service
        fi
        exec ${lib.getExe firn-boot} install "$1" --efi ${lib.escapeShellArg cfg.efiMountPoint} --apply
      '';
    };
  };
}

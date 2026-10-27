# Booting through the installer's m1n1: every generation is written into
# <ESP>/omarchy/boot.bin by m4-nix-boot.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.m4-j713;
  sources = pkgs.callPackage ../pkgs/sources.nix { };
  m4-nix-boot = pkgs.callPackage ../pkgs/m4-nix-boot { };
  # Cross-compiled on cfg.buildSystem, like the kernel.
  m1n1 =
    (import pkgs.path {
      localSystem = cfg.buildSystem;
      crossSystem = pkgs.stdenv.hostPlatform.system;
    }).callPackage
      ../pkgs/m1n1
      { };

  # m4-nix-boot reads the devicetree from <toplevel>/dtbs/apple/m4-nix-j713.dtb.
  dtb =
    if cfg.devicetree == "source" then
      "${config.boot.kernelPackages.kernel}/dtbs/apple/t8132-j713.dtb"
    else
      sources.dtb;
  dtbs = pkgs.runCommand "m4-j713-dtbs" { } ''
    install -Dm444 ${dtb} $out/apple/m4-nix-j713.dtb
  '';
in
{
  config = lib.mkIf cfg.enable {
    hardware.deviceTree = {
      enable = true;
      dtbSource = dtbs;
    };

    # m4-nix-boot writes <toplevel>/m1n1.bin into boot.bin when it exists.
    system.extraSystemBuilderCmds = lib.mkIf (cfg.loader == "source") ''
      ln -s ${m1n1}/lib/m1n1/m1n1.bin $out/m1n1.bin
    '';

    boot.initrd.systemd.enable = true;
    # The installer and m4-nix-boot both require one gzip initrd.
    boot.initrd.compressor = "gzip";

    environment.systemPackages = [
      m4-nix-boot
      (pkgs.callPackage ../pkgs/m4-nix-report { })
    ];

    # The installer creates the EFI system partition and m1n1 stage 1 passes its
    # partition UUID in the devicetree, so it is found at boot, not in fstab.
    systemd.services.m4-esp = {
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
        uuid=$(tr -d '\0' < '/proc/device-tree/chosen/gravity,efi-system-partition')
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
      installHook = pkgs.writeShellScript "m4-nix-boot-install" ''
        set -e
        if ! ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg cfg.efiMountPoint}; then
          ${config.systemd.package}/bin/systemctl start m4-esp.service
        fi
        exec ${lib.getExe m4-nix-boot} install "$1" --efi ${lib.escapeShellArg cfg.efiMountPoint} --apply ${
          lib.concatMapStringsSep " " (sha: "--allow-loader ${sha}") cfg.allowLoaders
        } ${lib.optionalString (cfg.devicetree == "source") "--allow-unpinned dtb"}
      '';
    };
  };
}

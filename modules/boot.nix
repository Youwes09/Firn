{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.firn;
  firn-boot = pkgs.callPackage ../pkgs/firn-boot { };
  m1n1 =
    (import pkgs.path {
      localSystem = cfg.buildSystem;
      crossSystem = pkgs.stdenv.hostPlatform.system;
    }).callPackage
      ../pkgs/m1n1
      { };
  # firn-boot needs the room on the 500 MB partition; Firn reads neither.
  esp-tidy = pkgs.writeShellScript "firn-esp-tidy" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    esp=${lib.escapeShellArg cfg.efiMountPoint}
    dest=/var/lib/firn/installer
    mkdir -p "$dest"
    chmod 700 "$dest"
    for name in gravity vendorfw; do
      [ -e "$esp/$name" ] || continue
      target=$dest/$name
      [ -e "$target" ] && target=$dest/$name-$(date +%Y%m%d%H%M%S)
      rm -rf "$target.part"
      cp -r --preserve=timestamps "$esp/$name" "$target.part"
      sync -f "$target.part"
      mv "$target.part" "$target"
      rm -rf "''${esp:?}/$name"
      echo "moved $esp/$name to $target"
    done
    sync -f "$esp"
  '';
in
{
  config = lib.mkIf cfg.enable {
    hardware.deviceTree = {
      enable = true;
      filter = "t8132-j713.dtb";
    };

    system.systemBuilderCommands = ''
      ln -s ${m1n1}/lib/m1n1/m1n1.bin $out/m1n1.bin
    '';

    boot.initrd.systemd.enable = true;
    # The installer and firn-boot require a gzip initrd.
    boot.initrd.compressor = "gzip";

    environment.systemPackages = [
      firn-boot
      (pkgs.callPackage ../pkgs/firn-report { })
    ];

    # m1n1 stage 1 names the installer's EFI partition in the devicetree.
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
        uuid=$(tr -d '\0' < '/proc/device-tree/chosen/gravity,efi-system-partition')
        case "$uuid" in
          ????????-????-????-????-????????????) ;;
          *) echo "m1n1 named no valid EFI partition: '$uuid'" >&2; exit 1 ;;
        esac
        device=/dev/disk/by-partuuid/''${uuid,,}
        udevadm wait --timeout=120 "$device"
        mkdir -p ${lib.escapeShellArg cfg.efiMountPoint}
        mount -t vfat -o umask=0077,nodev,nosuid,noexec "$device" ${lib.escapeShellArg cfg.efiMountPoint}
      '';
    };

    systemd.services.firn-esp-tidy = {
      description = "Move the installer's files off the EFI system partition";
      wantedBy = [ "multi-user.target" ];
      requires = [ "firn-esp.service" ];
      after = [ "firn-esp.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = esp-tidy;
      };
    };

    boot.loader.grub.enable = false;
    boot.loader.external = {
      enable = true;
      installHook = pkgs.writeShellScript "firn-boot-install" ''
        set -e
        if ! ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg cfg.efiMountPoint}; then
          ${config.systemd.package}/bin/systemctl start firn-esp.service
        fi
        # Not a unit: a generation installed with "boot" is not running yet.
        ${esp-tidy}
        exec ${lib.getExe firn-boot} install "$1" --efi ${lib.escapeShellArg cfg.efiMountPoint} --apply
      '';
    };
  };
}

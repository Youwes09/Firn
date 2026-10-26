# Installing from the J713 installer: the root filesystem starts as the image
# in our OS package, written to a partition the installer sizes, and the EFI
# system partition is the one the installer creates.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.m4-j713;
in
{
  options.hardware.m4-j713.image = {
    rootUuid = lib.mkOption {
      type = lib.types.strMatching "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
      default = "5b0c6f2e-8d4a-4e1b-9c3f-7a2d1e6b4f80";
      description = ''
        Filesystem UUID of the root image. The installer checks the image
        against it, and NixOS mounts the root by it.
      '';
    };
    label = lib.mkOption {
      type = lib.types.str;
      default = "m4-nixos";
      description = "Filesystem label of the root image.";
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems."/" = lib.mkDefault {
      device = "/dev/disk/by-uuid/${cfg.image.rootUuid}";
      fsType = "ext4";
      # The installer makes the partition larger than the image.
      autoResize = true;
    };

    # The image holds only /nix/store; register it and make the system profile
    # on first boot, as nixpkgs' SD-card images do.
    boot.postBootCommands = ''
      if [ -f /nix-path-registration ]; then
        set -euo pipefail
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
        touch /etc/NIXOS
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
        rm -f /nix-path-registration
      fi
    '';
  };
}

{
  config,
  lib,
  ...
}:
let
  cfg = config.hardware.firn;
in
{
  options.hardware.firn.image = {
    rootUuid = lib.mkOption {
      type = lib.types.strMatching "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
      default = "5b0c6f2e-8d4a-4e1b-9c3f-7a2d1e6b4f80";
      description = "Filesystem UUID of the root image; NixOS mounts the root by it.";
    };
    label = lib.mkOption {
      type = lib.types.str;
      default = "firn";
      description = "Filesystem label of the root image.";
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems."/" = lib.mkDefault {
      device = "/dev/disk/by-uuid/${cfg.image.rootUuid}";
      fsType = "ext4";
      autoResize = true;
    };

    # Grow before initrd activation fills the image's 16 MiB of free space.
    boot.initrd.systemd = {
      additionalUpstreamUnits = [ "systemd-growfs@.service" ];
      storePaths = [ "${config.boot.initrd.systemd.package}/lib/systemd/systemd-growfs" ];
    };

    # As nixpkgs' SD-card images.
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

{ lib, ... }:
{
  imports = [
    ./kernel.nix
    ./boot.nix
    ./firmware.nix
    ./power.nix
    ./image.nix
    ./link.nix
  ];

  options.hardware.firn = {
    enable = lib.mkEnableOption "NixOS on the 13-inch M4 MacBook Air (J713)";

    efiMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/boot/efi";
      description = "Where the EFI system partition holding m1n1/boot.bin is mounted.";
    };

    wifiRegion = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[A-Z]{2}");
      default = null;
      example = "US";
      description = ''
        ISO 3166 country code for Wi-Fi regulatory rules. Without it the kernel
        stays in the world region: 5 GHz is mostly passive or blocked and
        6 GHz is off.
      '';
    };

    buildSystem = lib.mkOption {
      type = lib.types.str;
      default = "x86_64-linux";
      description = "The machine that cross-compiles the kernel and m1n1.";
    };

    kernelCcache = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Compile the kernel through the build machine's ccache. That machine
        needs programs.ccache.enable and its cacheDir in
        nix.settings.extra-sandbox-paths.
      '';
    };
  };
}

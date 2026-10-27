# NixOS on the 13-inch M4 MacBook Air (Mac16,12 / J713).
{ lib, ... }:
{
  imports = [
    ./kernel.nix
    ./boot.nix
    ./firmware.nix
    ./power.nix
    ./image.nix
  ];

  options.hardware.m4-j713 = {
    enable = lib.mkEnableOption "NixOS on the 13-inch M4 MacBook Air (J713)";

    efiMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/boot/efi";
      description = "Where the EFI system partition holding omarchy/boot.bin is mounted.";
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

    loader = lib.mkOption {
      type = lib.types.enum [
        "installed"
        "source"
      ];
      default = "installed";
      description = ''
        The m1n1 stage 2 in boot.bin. "installed" keeps the installer's;
        "source" builds pkgs/m1n1 and makes it part of the generation, so a
        rollback to an older "source" generation restores its loader too.
      '';
    };

    devicetree = lib.mkOption {
      type = lib.types.enum [
        "release"
        "source"
      ];
      default = "release";
      description = ''
        The devicetree in boot.bin. "release" is Omarchy-M4-Native's
        j713-cputemp binary; "source" is t8132-j713.dtb built with the kernel
        from pkgs/linux/patches/topics.
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

    allowLoaders = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[0-9a-f]{64}");
      default = [ ];
      description = ''
        SHA-256 of m1n1 stage 2 loaders, read from your installed boot.bin with
        `m4-nix-boot inspect`, that you reviewed and accept although the tool
        does not know them.
      '';
    };
  };
}

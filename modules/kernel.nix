{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.firn;

  kernelPkgs = import pkgs.path {
    localSystem = cfg.buildSystem;
    crossSystem = pkgs.stdenv.hostPlatform.system;
  };
  kernel = kernelPkgs.callPackage ../pkgs/linux {
    kernelPatches = [ ];
    useCcache = cfg.kernelCcache;
    configfile = cfg.kernelConfig;
  };
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
        message = "hardware.firn needs nixpkgs.hostPlatform = \"aarch64-linux\".";
      }
    ];

    boot.kernelPackages = pkgs.linuxPackagesFor kernel;
    boot.kernelParams = [
      # firn-boot refuses a generation without maxcpus, idle and nowfxt.
      "maxcpus=10"
      "idle=nop"
      # WFIT in __delay() stops the M4 at EL2.
      "arm64.nowfxt"
      "panic=0"
      "console=tty0"
      "fbcon=nodefer"
      "log_buf_len=1M"
      # Otherwise an automount on /boot hides the firn-esp mount.
      "systemd.gpt_auto=0"
      "rd.systemd.gpt_auto=0"
      # Delayed flushes crash the storage coprocessor on some units
      # (Omarchy-M4-Native #167).
      "nvme_apple.flush_interval=0"
    ];
    boot.consoleLogLevel = 4;
    system.boot.loader.kernelFile = "Image.gz";

    boot.initrd.includeDefaultModules = false;
    boot.initrd.availableKernelModules = [ "nvme-apple" ];
  };
}

# The kernel, built from Asahi's tree with pkgs/linux/patches/topics, and its
# parameters.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.firn;

  # Cross-compiled on cfg.buildSystem; the Air never compiles a kernel.
  kernelPkgs = import pkgs.path {
    localSystem = cfg.buildSystem;
    crossSystem = pkgs.stdenv.hostPlatform.system;
  };
  kernel = kernelPkgs.callPackage ../pkgs/linux {
    kernelPatches = [ ];
    useCcache = cfg.kernelCcache;
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
      # The installer's ESP shares the disk with the root, so systemd's GPT
      # auto-generator would also mount it, as an automount on /boot, and
      # hide the firn-esp mount at /boot/efi underneath it.
      "systemd.gpt_auto=0"
      "rd.systemd.gpt_auto=0"
      # nvme-apple's delayed flush acknowledges a flush at once and sends its
      # own later; Omarchy-M4-Native issue #167 reports that this crashes the
      # storage coprocessor on some units. It does not prevent the crash in
      # docs/ISSUES.md.
      "nvme_apple.flush_interval=0"
    ];
    boot.consoleLogLevel = 4;
    system.boot.loader.kernelFile = "Image.gz";

    # Everything the root needs is built in except the Apple NVMe driver.
    boot.initrd.includeDefaultModules = false;
    boot.initrd.availableKernelModules = [ "nvme-apple" ];
  };
}

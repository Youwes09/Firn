# T1: what the built system must and must not contain, checked from its
# evaluated configuration. Fails with every violated rule listed.
{ pkgs, nixos }:
let
  inherit (pkgs) lib;
  cfg = nixos.config;
  kernel = cfg.boot.kernelPackages.kernel;
  params = cfg.boot.kernelParams;
  login = cfg.services.logind.settings.Login;
  sleep = cfg.systemd.sleep.settings.Sleep;

  rules = {
    "kernel is this repository's source build" =
      kernel.modDirVersion == "7.1.9-m4-gpu-backport-20261008";
    "the kernel builds no GPU or speaker codec driver" =
      lib.all
        (
          option:
          !(lib.elem (kernel.config."CONFIG_${option}" or "n") [
            "y"
            "m"
          ])
        )
        [
          "DRM_ASAHI"
          "SND_SOC_TAS2764"
          "SND_SOC_TAS2770"
          "SND_SOC_APPLE_MCA"
          "SND_SOC_CS42L84"
        ];
    "no out-of-tree modules" = cfg.boot.extraModulePackages == [ ];
    "no kernel patches from the configuration" = cfg.boot.kernelPatches == [ ];
    "no devicetree overlays" = cfg.hardware.deviceTree.overlays == [ ];
    "kernel parameters keep the hardware switches" = lib.all (p: lib.elem p params) [
      "maxcpus=10"
      "idle=nop"
      "arm64.nowfxt"
    ];
    "nvme-apple's delayed flush is off (#167)" = lib.elem "nvme_apple.flush_interval=0" params;
    "kernel parameters do not set init= or idle= twice" =
      !(lib.any (lib.hasPrefix "init=") params)
      && lib.length (lib.filter (lib.hasPrefix "idle=") params) == 1;
    "suspend and hibernate are off" =
      sleep.AllowSuspend == "no"
      && sleep.AllowHibernation == "no"
      && sleep.AllowHybridSleep == "no"
      && sleep.AllowSuspendThenHibernate == "no";
    "closing the lid powers off" =
      login.HandleLidSwitch == "poweroff" && login.HandleLidSwitchExternalPower == "poweroff";
    "initrd is gzip, as the installer requires" = cfg.boot.initrd.compressor == "gzip";
    "boot.bin is written by m4-nix-boot" =
      cfg.boot.loader.external.enable && !cfg.boot.loader.grub.enable;
    "no audio server is enabled" =
      !cfg.services.pipewire.enable && !(cfg.services.pulseaudio.enable or false);
    "no graphics stack is enabled" = !cfg.hardware.graphics.enable;
  };
  failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) rules);
in
pkgs.runCommand "m4-nix-policy" { } (
  if failed == [ ] then
    ''
      cat > $out <<'EOF'
      ${lib.concatMapStrings (r: "ok: ${r}\n") (lib.attrNames rules)}
      EOF
    ''
  else
    throw "M4-Nix policy violated:\n${lib.concatMapStrings (r: "  - ${r}\n") failed}"
)

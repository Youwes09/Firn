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

  qualified = [
    "maxcpus=10"
    "idle=nop"
    "panic=0"
    "console=tty0"
    "fbcon=nodefer"
    "log_buf_len=1M"
    "m4trace_hit=999"
    "dockchannel_hid.m4_power_v2=1"
    "pcie_apple.m4_link_diag=1"
    "pcie_apple.m4_keep_clocks=1"
    "dockchannel_hid.m4_afe_action=1"
  ];
  offModules = [
    "snd_soc_tas2764"
    "snd_soc_tas2770"
    "snd_soc_apple_mca"
    "snd_soc_macaudio"
    "snd_soc_cs42l84"
  ];
  unported = [
    "speakers"
    "headphones"
    "gpu"
    "cpuIdle"
    "cpuBoost"
    "backlight"
    "frontUsb"
    "notch"
  ];

  rules = {
    "kernel is the pinned linux-m4 build" =
      kernel.pname == "linux-m4-j713" && kernel.modDirVersion == "7.1.9-m4-gpu-backport-20261008";
    "no out-of-tree kernel modules" = cfg.boot.extraModulePackages == [ ];
    "no kernel patches" = cfg.boot.kernelPatches == [ ];
    "no devicetree overlays" = cfg.hardware.deviceTree.overlays == [ ];
    "kernel parameters keep every qualified switch" = lib.all (p: lib.elem p params) qualified;
    "kernel parameters do not set init= or idle= twice" =
      !(lib.any (lib.hasPrefix "init=") params)
      && lib.length (lib.filter (lib.hasPrefix "idle=") params) == 1;
    "speaker and headphone drivers are blacklisted" = lib.all (
      m: lib.elem m cfg.boot.blacklistedKernelModules
    ) offModules;
    "no off-profile driver is loaded explicitly" =
      !(lib.any (m: lib.elem m offModules) (cfg.boot.kernelModules ++ cfg.boot.initrd.kernelModules));
    "every unported option is off" = lib.all (n: !cfg.hardware.m4-j713.${n}.enable) unported;
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

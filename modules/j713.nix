# NixOS on the 13-inch M4 MacBook Air (Mac16,12 / J713), minimal-risk profile.
#
# On: the published kernel, the j713-cputemp devicetree (poweroff fix, CPU
# clocks capped at what iBoot hands over, reporting-only temperatures), NVMe,
# keyboard, trackpad, Wi-Fi, hinge-side USB-C, simpledrm display.
#
# Off: everything with a hardware-damage or boot risk until it is ported and
# reviewed. Each such option exists only so that turning it on fails loudly.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.m4-j713;

  kernel = pkgs.callPackage ../pkgs/linux-m4.nix { kernelPatches = [ ]; };
  sources = pkgs.callPackage ../pkgs/sources.nix { };
  m4-nix-boot = pkgs.callPackage ../pkgs/m4-nix-boot { };

  # The update 4 installer's boot arguments, which the kernel was qualified
  # with. loglevel=4 comes from boot.consoleLogLevel. m4-nix-boot refuses a
  # generation that drops any of the hardware switches.
  qualifiedParams = [
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

  # m4-nix-boot reads the devicetree from <toplevel>/dtbs/apple/m4-nix-j713.dtb.
  dtbs = pkgs.runCommand "m4-j713-dtbs" { } ''
    install -Dm444 ${sources.dtb} $out/apple/m4-nix-j713.dtb
  '';

  unported = {
    speakers = "Speakers need the protected audio stack (speakersafetyd, filters, modules); without it the amplifiers can be damaged.";
    headphones = "The headphone jack's devicetree overlay depends on the speaker overlays.";
    gpu = "The GPU needs the out-of-tree asahi_m4 module and the matching Mesa, whose build is unverified.";
    cpuIdle = "CPU idle needs the out-of-tree j713_cpuidle module.";
    cpuBoost = "Clocks above iBoot's handover need the j713_pguard heat guard and a later devicetree.";
    backlight = "Native backlight replaces the m1n1 stage 2 loader and needs its devicetree.";
    frontUsb = "The front USB-C port needs the j713-usb0 devicetree.";
    notch = "Notch mode replaces the m1n1 stage 2 loader.";
  };

  # Drivers for hardware that is off in this profile. The speaker amplifiers
  # are only described by runtime overlays this profile never loads; these
  # stay unloaded as well in case something else describes them.
  blacklisted = [
    "snd_soc_tas2764"
    "snd_soc_tas2770"
    "snd_soc_apple_mca"
    "snd_soc_macaudio"
    "snd_soc_cs42l84"
  ];
in
{
  imports = [ ./image.nix ];

  options.hardware.m4-j713 = {
    enable = lib.mkEnableOption "NixOS on the 13-inch M4 MacBook Air (J713), minimal-risk profile";

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

    allowLoaders = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[0-9a-f]{64}");
      default = [ ];
      description = ''
        SHA-256 of m1n1 stage 2 loaders, read from your installed boot.bin with
        `m4-nix-boot inspect`, that you reviewed and accept although the tool
        does not know them.
      '';
    };
  }
  // lib.mapAttrs (name: reason: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Not ported. ${reason}";
    };
  }) unported;

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
        message = "hardware.m4-j713 needs nixpkgs.hostPlatform = \"aarch64-linux\".";
      }
    ]
    ++ lib.mapAttrsToList (name: reason: {
      assertion = !cfg.${name}.enable;
      message = "hardware.m4-j713.${name}.enable is not ported yet. ${reason}";
    }) unported;

    boot.kernelPackages = pkgs.linuxPackagesFor kernel;
    # The installer's ESP shares the disk with the root, so systemd's GPT
    # auto-generator would also mount it, as an automount on /boot, and hide
    # the m4-esp mount at /boot/efi underneath it.
    boot.kernelParams = qualifiedParams ++ [
      "systemd.gpt_auto=0"
      "rd.systemd.gpt_auto=0"
    ];
    boot.consoleLogLevel = 4;
    system.boot.loader.kernelFile = "Image.gz";
    hardware.deviceTree = {
      enable = true;
      dtbSource = dtbs;
    };

    # Everything the root needs is built in except the Apple NVMe driver.
    boot.initrd.includeDefaultModules = false;
    boot.initrd.availableKernelModules = [ "nvme-apple" ];
    boot.initrd.systemd.enable = true;
    # The installer and m4-nix-boot both require one gzip initrd.
    boot.initrd.compressor = "gzip";
    boot.blacklistedKernelModules = blacklisted;

    # Apple firmware arrives at /vendorfw in the initramfs (m4-nix-boot carries
    # it over from the installer's boot.bin). Copy it to /run, which survives
    # switch-root, and let the kernel's /lib/firmware fallback find it. The link
    # is made by activation, which runs before udev starts loading drivers.
    boot.initrd.systemd.tmpfiles.settings."10-m4-vendorfw"."/run/vendorfw".C.argument = "/vendorfw";
    system.activationScripts.m4-vendorfw = ''
      mkdir -p /lib
      ln -sfn /run/vendorfw /lib/firmware
    '';

    # The kernel only accepts the signed regulatory.db, which NixOS puts on the
    # firmware_class search path; /lib/firmware stays the fallback for Apple's.
    hardware.wirelessRegulatoryDatabase = cfg.wifiRegion != null;
    boot.extraModprobeConfig = lib.mkIf (cfg.wifiRegion != null) ''
      options cfg80211 ieee80211_regdom="${cfg.wifiRegion}"
    '';

    # Suspend and hibernate are not qualified on this hardware. A closed lid
    # powers off rather than leaving the Air running in a bag.
    systemd.sleep.settings.Sleep = {
      AllowSuspend = "no";
      AllowHibernation = "no";
      AllowHybridSleep = "no";
      AllowSuspendThenHibernate = "no";
    };
    services.logind.settings.Login = {
      HandleLidSwitch = "poweroff";
      HandleLidSwitchExternalPower = "poweroff";
      HandleLidSwitchDocked = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
    };

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
        }
      '';
    };
  };
}

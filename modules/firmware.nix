# Apple firmware from the installer, and Wi-Fi regulatory rules.
{ config, lib, ... }:
let
  cfg = config.hardware.m4-j713;
in
{
  config = lib.mkIf cfg.enable {
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
  };
}

{ config, lib, ... }:
let
  cfg = config.hardware.firn;
in
{
  config = lib.mkIf cfg.enable {
    # /run survives switch-root; activation links it before udev loads drivers.
    boot.initrd.systemd.tmpfiles.settings."10-firn-vendorfw"."/run/vendorfw".C.argument = "/vendorfw";
    system.activationScripts.firn-vendorfw = ''
      mkdir -p /lib
      ln -sfn /run/vendorfw /lib/firmware
    '';

    hardware.wirelessRegulatoryDatabase = cfg.wifiRegion != null;
    boot.extraModprobeConfig = lib.mkIf (cfg.wifiRegion != null) ''
      options cfg80211 ieee80211_regdom="${cfg.wifiRegion}"
    '';
  };
}

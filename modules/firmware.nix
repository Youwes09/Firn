{
  config,
  lib,
  pkgs,
  ...
}:
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

    # USB-C Ethernet adapters with an RTL8153 load a firmware patch.
    hardware.firmware = [
      (pkgs.runCommand "rtl8153-firmware" { } ''
        install -Dm444 -t $out/lib/firmware/rtl_nic ${pkgs.linux-firmware}/lib/firmware/rtl_nic/rtl8153*.fw
      '')
    ];

    hardware.wirelessRegulatoryDatabase = cfg.wifiRegion != null;
    boot.extraModprobeConfig = lib.mkIf (cfg.wifiRegion != null) ''
      options cfg80211 ieee80211_regdom="${cfg.wifiRegion}"
    '';
  };
}

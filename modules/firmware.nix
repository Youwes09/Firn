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
    # Drivers that bind in the initrd, such as the trackpad's, find it here.
    # Stage 2 sets its own path and keeps /lib/firmware.
    boot.kernelParams = [ "firmware_class.path=/vendorfw" ];
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

    # cfg80211 loads it at boot, region set or not.
    hardware.wirelessRegulatoryDatabase = true;
    boot.extraModprobeConfig = lib.mkIf (cfg.wifiRegion != null) ''
      options cfg80211 ieee80211_regdom="${cfg.wifiRegion}"
    '';
  };
}

{ lib, pkgs, ... }:
{
  # Machine-local, gitignored.
  imports = lib.optional (builtins.pathExists ./access.nix) ./access.nix;

  hardware.firn.enable = true;
  hardware.firn.wifiRegion = "US";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = "m4-air";
  networking.wireless.iwd.enable = true;
  # Ethernet and Wi-Fi on one network otherwise fail DHCP's conflict check.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
  };

  hardware.bluetooth.enable = true;

  users.users.m4 = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "change-me";
  };

  environment.systemPackages = with pkgs; [
    iw
    lm_sensors
    pciutils
    tmux
    usbutils
  ];

  system.stateVersion = "26.05";
}

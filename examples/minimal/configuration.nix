# A console-only NixOS for the J713 with the minimal-risk profile.
# The root filesystem and the EFI system partition come from the module.
{ lib, pkgs, ... }:
{
  # Machine-local settings such as SSH keys, kept out of git.
  imports = lib.optional (builtins.pathExists ./access.nix) ./access.nix;

  hardware.firn.enable = true;
  hardware.firn.wifiRegion = "US";

  # For `nixos-rebuild --flake` and `nix shell` on the Air.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = "m4-air";
  networking.wireless.iwd.enable = true;
  # With Ethernet and Wi-Fi on one network, answer ARP only on the interface
  # that owns the address, so DHCP does not see its own other link as a conflict.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
  };

  hardware.bluetooth.enable = true;

  users.users.m4 = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # Change it at first login with passwd.
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

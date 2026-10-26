# A console-only NixOS for the J713 with the minimal-risk profile.
# The root filesystem and the EFI system partition come from the module.
{ lib, pkgs, ... }:
{
  # Machine-local settings such as SSH keys, kept out of git.
  imports = lib.optional (builtins.pathExists ./access.nix) ./access.nix;

  hardware.m4-j713.enable = true;
  hardware.m4-j713.wifiRegion = "US";

  # For `nixos-rebuild --flake` and `nix shell` on the Air.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = "m4-air";
  networking.wireless.iwd.enable = true;

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
    usbutils
  ];

  system.stateVersion = "26.05";
}

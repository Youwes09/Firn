{
  lib,
  writeShellApplication,
  coreutils,
  gawk,
  gnugrep,
  iproute2,
  util-linux,
  systemd,
  callPackage,
}:
writeShellApplication {
  name = "m4-nix-report";
  runtimeInputs = [
    coreutils
    gawk
    gnugrep
    iproute2
    util-linux
    systemd
    (callPackage ../m4-nix-boot { })
  ];
  # The script sets its own options and reads optional files that may be absent.
  bashOptions = [ ];
  text = lib.readFile ./m4-nix-report.sh;
}

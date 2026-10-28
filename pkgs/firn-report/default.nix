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
  name = "firn-report";
  runtimeInputs = [
    coreutils
    gawk
    gnugrep
    iproute2
    util-linux
    systemd
    (callPackage ../firn-boot { })
  ];
  # The script sets its own options and reads optional files that may be absent.
  bashOptions = [ ];
  text = lib.readFile ./firn-report.sh;
}

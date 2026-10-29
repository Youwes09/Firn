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
  bashOptions = [ ];
  text = lib.readFile ./firn-report.sh;
}

{
  lib,
  applyPatches,
  fetchFromGitHub,
}:
applyPatches {
  name = "gravity-installer-firn";
  src = fetchFromGitHub {
    owner = "GravityLinux";
    repo = "installer";
    rev = "6420623289fe7544cb8589b658355e57f0290fcc";
    hash = "sha256-YWT3AWa9hNVJKnSYwvWh0NkmX5/8nF8E0pOSR7TC/A8=";
  };
  patches = lib.filesystem.listFilesRecursive ./patches;
}

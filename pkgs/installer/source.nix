{
  lib,
  applyPatches,
  fetchFromGitHub,
}:
applyPatches {
  name = "asahi-installer-firn";
  src = fetchFromGitHub {
    owner = "AsahiLinux";
    repo = "asahi-installer";
    rev = "e93743d52178b3e26e428fa05174ef549abf30cb";
    hash = "sha256-KTl4GsCz/PdrzWmR/y12N1Lmw1f7Auzh2EYwcTjuCo0=";
  };
  patches = lib.filesystem.listFilesRecursive ./patches;
}

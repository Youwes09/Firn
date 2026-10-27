# Mesa for the M4 GPU (Apple GPU family 9): GravityLinux's fork at the commit
# Omarchy-M4-Native's GPU stack was built from, with their four-file fix-up
# (compressed formats, external samplers, imported modifiers). Only the asahi
# Gallium driver and Wayland EGL/GBM, as in their build.
#
# Apply it to the build and host package sets alike (an overlay), so that a
# cross build uses this fork's own asahi_clc from buildPackages.mesa.
{
  lib,
  mesa,
  fetchFromGitHub,
}:
(mesa.override {
  galliumDrivers = [ "asahi" ];
  vulkanDrivers = [ ];
  vulkanLayers = [ ];
  eglPlatforms = [ "wayland" ];
}).overrideAttrs
  (old: {
    version = "26.3.0-unstable-2026-09-22";

    src = fetchFromGitHub {
      owner = "GravityLinux";
      repo = "mesa";
      rev = "87ac51d411f0e58a9433567ec2666f457be89e1d";
      hash = "sha256-KR6WdlY6oLPKdk+LgpLVvb9jzlwJYi/ht9KxrGJUqM4=";
    };

    patches = [ ./patches/gravity-apple9-fixes.patch ];

    # nixpkgs checks the GL headers against its own Mesa release's.
    postPatch = ''
      patchShebangs .
    '';

    # OpenCL (Rusticl) and Teflon need Rust crates pinned for nixpkgs' Mesa
    # release, and the M4 build did not include them. Later -D options win.
    mesonFlags = old.mesonFlags ++ [
      (lib.mesonBool "gallium-rusticl" false)
      (lib.mesonBool "teflon" false)
    ];
  })

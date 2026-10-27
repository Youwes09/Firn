# m1n1 stage 2 for J713: upstream m1n1 at the commit Omarchy-M4-Native's
# qualified loader was built from, with their M4 GPU handoff patch and their
# release flags (no display, no chainloading).
{
  m1n1,
  fetchFromGitHub,
  rustPlatform,
}:
(m1n1.override { customLogo = null; }).overrideAttrs (
  finalAttrs: old: {
    version = "1.6.1-unstable-2026-07-19";

    src = fetchFromGitHub {
      owner = "AsahiLinux";
      repo = "m1n1";
      rev = "c9ef56f7356e93e6f6cac116c529d31c277ef6a6";
      hash = "sha256-iv7ANQQ/UsYB1Y9fXNgHffDHT+Hd7ek2Nn2oDus21UA=";
    };

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit (finalAttrs) pname version;
      src = "${finalAttrs.src}/rust";
      sourceRoot = "rust";
      hash = "sha256-7G9aTQEiQ8ocsY0gSoBg9A2cusfqR4a1nhFikpWMXAA=";
    };

    patches = [
      ./patches/omarchy-stage2.patch
      ./patches/0001-kboot-Reserve-the-trust-cache.patch
    ];

    makeFlags = [
      "ARCH=${m1n1.stdenv.cc.targetPrefix}"
      "RELEASE=1"
      "CHAINLOADING=0"
      "NO_DISPLAY=1"
    ];

    env = (old.env or { }) // {
      M1N1_VERSION_TAG = "m4-nix-c9ef56f-stage2";
    };
  }
)

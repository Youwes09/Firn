# m1n1 for the J713, both stages from one upstream commit.
#
# Stage 1 is the boot object the installer registers in the stub macOS; it
# loads stage 2 from the EFI partition. Stage 2 boots Linux from the payloads
# appended to it in boot.bin.
{
  lib,
  m1n1,
  fetchFromGitHub,
  rustPlatform,
  stage ? 2,
}:
assert lib.elem stage [
  1
  2
];
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

    patches = lib.filesystem.listFilesRecursive (./patches + "/stage${toString stage}");

    makeFlags = [
      "ARCH=${m1n1.stdenv.cc.targetPrefix}"
      "RELEASE=1"
      "CHAINLOADING=${if stage == 1 then "1" else "0"}"
      # m1n1 cannot drive the M4's display (DCP) yet.
      "NO_DISPLAY=1"
    ];

    env = (old.env or { }) // {
      M1N1_VERSION_TAG = "firn-c9ef56f-stage${toString stage}";
    };
  }
)

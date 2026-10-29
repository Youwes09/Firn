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
(m1n1.override { customLogo = ../../artwork/firn-logo.png; }).overrideAttrs (
  finalAttrs: old: {
    version = "1.6.1-unstable-2026-10-14";

    src = fetchFromGitHub {
      owner = "GravityLinux";
      repo = "bootloader";
      rev = "f02d4a52017915febb222539636b5b025a70407a";
      fetchSubmodules = true;
      hash = "sha256-9OPkQgDi2PTqfZCi0F9G3mu4URLArQgy151hd43Da48=";
    };

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit (finalAttrs) pname version;
      src = "${finalAttrs.src}/rust";
      sourceRoot = "rust";
      hash = "sha256-/2JQ31pMHbNjZsIu2RLCWzNul/qzL1O2+XB3qdOEb2U=";
    };

    patches = lib.filesystem.listFilesRecursive (./patches + "/stage${toString stage}");

    makeFlags = [
      "ARCH=${m1n1.stdenv.cc.targetPrefix}"
      "RELEASE=1"
      "CHAINLOADING=${if stage == 1 then "1" else "0"}"
      "LOGO=custom"
      # No DCP support for the M4 yet.
      "NO_DISPLAY=1"
    ];

    installPhase = ''
      runHook preInstall
      install -Dm644 build/m1n1.bin -t $out/lib/m1n1/
      install -Dm644 LICENSE.* 3rdparty_licenses/LICENSE.* -t $out/share/doc/m1n1/licenses/
      runHook postInstall
    '';

    env = (old.env or { }) // {
      M1N1_VERSION_TAG = "firn-f02d4a5-stage${toString stage}";
    };
  }
)

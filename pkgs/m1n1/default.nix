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
    version = "1.6.1-unstable-2026-11-15";

    src = fetchFromGitHub {
      owner = "GravityLinux";
      repo = "bootloader";
      rev = "8d7217dabe8ad677ea7f1054ed3b29a66291e8a7";
      fetchSubmodules = true;
      hash = "sha256-gHZSyy2u80JoRRb/ZAuJro+q9UgKVqb/Wo45MwwIuq0=";
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
      M1N1_VERSION_TAG = "firn-8d7217d-stage${toString stage}";
    };
  }
)

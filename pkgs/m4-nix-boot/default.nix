{
  lib,
  stdenvNoCC,
  callPackage,
  python3,
}:
let
  sources = callPackage ../sources.nix { };
in
stdenvNoCC.mkDerivation {
  pname = "m4-nix-boot";
  version = "0.2.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./m4-nix-boot.py
      ./test_m4_nix_boot.py
    ];
  };

  nativeBuildInputs = [ python3 ];
  buildInputs = [ python3 ];

  # The installer's own boot.bin writer, for the contract tests.
  M4BOOT_PY = sources.installerM4boot;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -I -m unittest discover -s . -p 'test_*.py' -v 2>&1 | tee test.log
    grep -q 'skipped' test.log && { echo "contract tests did not run" >&2; exit 1; }
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 m4-nix-boot.py $out/bin/m4-nix-boot
    patchShebangs --host $out/bin/m4-nix-boot
    runHook postInstall
  '';

  meta = {
    description = "Write the J713 m1n1 boot.bin for a NixOS generation";
    mainProgram = "m4-nix-boot";
    platforms = lib.platforms.linux;
  };
}

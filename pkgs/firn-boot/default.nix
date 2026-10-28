{
  lib,
  stdenvNoCC,
  callPackage,
  python3,
}:
let
  # The installer's source, whose payloads.py writes the first boot.bin.
  installer = callPackage ../installer/source.nix { };
in
stdenvNoCC.mkDerivation {
  pname = "firn-boot";
  version = "0.4.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./firn-boot.py
      ./test_firn_boot.py
    ];
  };

  nativeBuildInputs = [ python3 ];
  buildInputs = [ python3 ];

  PAYLOADS_PY = "${installer}/src/payloads.py";

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -I -m unittest discover -s . -p 'test_*.py' -v 2>&1 | tee test.log
    grep -q 'skipped' test.log && { echo "contract tests did not run" >&2; exit 1; }
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 firn-boot.py $out/bin/firn-boot
    patchShebangs --host $out/bin/firn-boot
    runHook postInstall
  '';

  meta = {
    description = "Write the J713 m1n1 boot.bin for a NixOS generation";
    mainProgram = "firn-boot";
    platforms = lib.platforms.linux;
  };
}

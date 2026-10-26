# The J713 kernel exactly as Omarchy-M4-Native publishes it: the prebuilt
# Image.gz and modules from the linux-m4-omarchy payload, not a source build.
# Using the published bytes keeps the kernel the one that was tested on the Air.
#
# kernelPatches, randstructSeed and features are accepted because NixOS calls
# kernel.override with them; a prebuilt kernel can honour none but the defaults.
{
  lib,
  stdenvNoCC,
  callPackage,
  zstd,
  kmod,
  kernelPatches ? [ ],
  randstructSeed ? "",
  features ? { },
  ...
}:
let
  sources = callPackage ./sources.nix { };
  version = "7.1.9";
  modDirVersion = "7.1.9-m4-gpu-backport-20261008";
  configfile = ./kernel.config;

  # Same parse as nixpkgs' kernel/build.nix readConfig: only =y and =m lines.
  parsed = lib.listToAttrs (
    lib.concatMap (
      line:
      let
        m = lib.match "(CONFIG_[^=]+)=([ym])" line;
      in
      lib.optional (m != null) {
        name = lib.elemAt m 0;
        value = lib.elemAt m 1;
      }
    ) (lib.splitString "\n" (builtins.readFile configfile))
  );
  config =
    let
      name = attr: "CONFIG_" + attr;
    in
    rec {
      isSet = attr: parsed ? ${name attr};
      getValue = attr: parsed.${name attr} or null;
      isYes = attr: getValue attr == "y";
      isNo = attr: getValue attr == "n";
      isModule = attr: getValue attr == "m";
      isEnabled = attr: isModule attr || isYes attr;
      isDisabled = attr: !(isSet attr) || isNo attr;
    }
    // parsed;
in
assert lib.assertMsg (
  kernelPatches == [ ]
) "linux-m4 is a prebuilt kernel; boot.kernelPatches cannot apply to it";
assert lib.assertMsg (
  randstructSeed == ""
) "linux-m4 is a prebuilt kernel; it has no randstruct seed to set";
stdenvNoCC.mkDerivation {
  pname = "linux-m4-j713";
  inherit version;

  src = sources.kernelPayload;
  nativeBuildInputs = [
    zstd
    kmod
  ];
  dontUnpack = true;
  dontStrip = true;
  dontPatchELF = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir payload
    tar --zstd -xf $src -C payload
    echo "${sources.kernelImageSha256}  payload/usr/lib/omarchy-m4/Image.gz" | sha256sum -c -
    cmp payload/usr/lib/omarchy-m4/kernel.config ${configfile}
    test -d payload/usr/lib/modules/${modDirVersion}

    mkdir -p $out/lib $out/share
    cp payload/usr/lib/omarchy-m4/Image.gz $out/Image.gz
    cp payload/usr/lib/omarchy-m4/kernel.config $out/config
    cp -r payload/usr/lib/modules $out/lib/modules
    cp -r payload/usr/share/licenses $out/share/licenses

    # The payload has no depmod output, and NixOS only runs depmod itself when
    # it merges several module packages, so a single kernel must carry it.
    depmod -b $out -a ${modDirVersion}
    test -s $out/lib/modules/${modDirVersion}/modules.dep
    test -s $out/lib/modules/${modDirVersion}/modules.builtin.alias.bin
    runHook postInstall
  '';

  passthru = {
    inherit
      modDirVersion
      configfile
      config
      features
      kernelPatches
      randstructSeed
      ;
    target = "Image.gz";
    isModular = true;
    isHardened = false;
    isLibre = false;
    isZen = false;
    withRust = config.isYes "RUST";
    kernelOlder = lib.versionOlder version;
    kernelAtLeast = lib.versionAtLeast version;
  };

  meta = {
    description = "Prebuilt Omarchy-M4-Native kernel for the 13-inch M4 MacBook Air (J713)";
    homepage = "https://github.com/Kb2uka/Omarchy-M4-Native";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

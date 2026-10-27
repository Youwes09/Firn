# The J713 kernel built from source: Asahi's release tree plus our patches,
# with the configuration Omarchy-M4-Native qualified (clang/LLVM, Rust).
{
  lib,
  fetchFromGitHub,
  linuxKernel,
  llvmPackages_21,
  ccache,
  # Compile through the host's ccache (/var/cache/ccache, which must be in
  # nix.settings.extra-sandbox-paths). It changes no output, only build time.
  useCcache ? false,
  # Passed by NixOS (boot.kernelPatches and friends); applied after ours.
  kernelPatches ? [ ],
  randstructSeed ? "",
  features ? { },
}:
(linuxKernel.manualConfig {
  inherit randstructSeed features;
  version = "7.1.9";
  # The configuration keeps the qualified kernel's LOCALVERSION.
  modDirVersion = "7.1.9-m4-gpu-backport-20261008";

  src = fetchFromGitHub {
    owner = "AsahiLinux";
    repo = "linux";
    tag = "asahi-7.1.9-1";
    hash = "sha256-5XxxWLbd7TN6qblIOwCzyk1zujbCAs06bXFwCxlzoX0=";
  };

  # The J713 series on top of asahi-7.1.9-1, one change per patch, in order.
  kernelPatches =
    map (name: {
      inherit name;
      patch = ./patches/topics + "/${name}";
    }) (lib.attrNames (builtins.readDir ./patches/topics))
    ++ kernelPatches;

  # Their configuration reduced to the modules this Air uses or may plug in
  # (localmodconfig), with the M4 GPU and the speaker codecs off: nothing may
  # load them until they are ported.
  configfile = ./j713.config;
  allowImportFromDerivation = true;

  stdenv = llvmPackages_21.stdenv;
  extraMakeFlags = [
    "LLVM=1"
  ]
  # Later CC= wins over the unwrapped clang the kernel build sets.
  ++ lib.optional useCcache "CC=${lib.getExe ccache} ${lib.getExe llvmPackages_21.stdenv.cc.cc}";

  extraMeta.platforms = [ "aarch64-linux" ];
}).overrideAttrs
  (
    old:
    {
      # m1n1 boots Image.gz, which the aarch64 platform default ("Image") would
      # not build. EFI_ZBOOT is off in the configuration, so zinstall installs it.
      buildFlags = map (flag: if flag == "Image" then "Image.gz" else flag) old.buildFlags;
      installTargets = [ "zinstall" ];
    }
    // lib.optionalAttrs useCcache {
      CCACHE_DIR = "/var/cache/ccache";
      CCACHE_UMASK = "007";
      # Generated headers get new timestamps in every build.
      CCACHE_SLOPPINESS = "include_file_mtime,include_file_ctime,time_macros";
    }
  )

{
  lib,
  fetchFromGitHub,
  linuxKernel,
  llvmPackages_21,
  buildPackages,
  # Needs /var/cache/ccache in nix.settings.extra-sandbox-paths.
  useCcache ? false,
  kernelPatches ? [ ],
  randstructSeed ? "",
  features ? { },
  # The M4 GPU and speaker codecs stay off until they are ported.
  configfile ? ./j713.config,
}:
(linuxKernel.manualConfig {
  inherit randstructSeed features configfile;
  version = "7.1.9";
  # Must match CONFIG_LOCALVERSION.
  modDirVersion = "7.1.9-firn";

  src = fetchFromGitHub {
    owner = "AsahiLinux";
    repo = "linux";
    tag = "asahi-7.1.9-1";
    hash = "sha256-5XxxWLbd7TN6qblIOwCzyk1zujbCAs06bXFwCxlzoX0=";
  };

  kernelPatches =
    map (name: {
      inherit name;
      patch = ./patches/topics + "/${name}";
    }) (lib.attrNames (builtins.readDir ./patches/topics))
    ++ kernelPatches;

  allowImportFromDerivation = true;

  stdenv = llvmPackages_21.stdenv;
  extraMakeFlags = [
    "LLVM=1"
  ]
  # Overrides the unwrapped clang the kernel build sets.
  ++ lib.optional useCcache "CC=${lib.getExe buildPackages.ccache} ${lib.getExe llvmPackages_21.stdenv.cc.cc}";

  extraMeta.platforms = [ "aarch64-linux" ];
}).overrideAttrs
  (
    old:
    {
      # m1n1 boots Image.gz.
      buildFlags = map (flag: if flag == "Image" then "Image.gz" else flag) old.buildFlags;
      installTargets = [ "zinstall" ];
    }
    // lib.optionalAttrs useCcache {
      # Structured attributes export only env.
      env = (old.env or { }) // {
        CCACHE_DIR = "/var/cache/ccache";
        CCACHE_UMASK = "007";
        CCACHE_SLOPPINESS = "include_file_mtime,include_file_ctime,time_macros";
      };
    }
  )

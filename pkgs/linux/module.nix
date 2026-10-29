# Rebuilds one driver directory against a finished kernel; installs to updates/.
{
  lib,
  kernel,
  pname,
  dir,
  modules,
  patches ? [ ],
}:
kernel.stdenv.mkDerivation {
  inherit pname patches;
  inherit (kernel) src version;

  nativeBuildInputs = kernel.moduleBuildDependencies;
  # Keeps __FILE__ strings from referencing the build tree.
  disallowedReferences = [ kernel.dev ];

  buildPhase = ''
    runHook preBuild
    make ${lib.escapeShellArgs kernel.commonMakeFlags} \
      -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      KCFLAGS=-fmacro-prefix-map=${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/= \
      M=$PWD/${dir} modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    for module in ${lib.escapeShellArgs modules}; do
      install -Dm444 ${dir}/$module.ko \
        $out/lib/modules/${kernel.modDirVersion}/updates/$module.ko
    done
    runHook postInstall
  '';

  meta.platforms = [ "aarch64-linux" ];
}

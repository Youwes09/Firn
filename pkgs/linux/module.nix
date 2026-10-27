# Build one in-tree driver directory against a finished kernel, so changing
# that driver rebuilds only its modules. They install under updates/, which
# modprobe prefers over the kernel's own copies.
{
  lib,
  kernel,
  pname,
  # The driver directory, relative to the kernel source.
  dir,
  # The module names to install from it.
  modules,
  patches ? [ ],
}:
kernel.stdenv.mkDerivation {
  inherit pname patches;
  inherit (kernel) src version;

  nativeBuildInputs = kernel.moduleBuildDependencies;
  # The kernel's headers reach the module only as __FILE__ strings; mapped as
  # an in-tree build maps them, the module does not keep the build tree alive.
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

# Mesa from Gravity Linux, whose asahi drivers render on the M4's G16 GPU
# through Firn's asahi_m4 kernel driver. Built on nixpkgs' Mesa, with only
# the drivers this machine runs: asahi, and llvmpipe and lavapipe for
# software rendering.
{
  lib,
  mesa,
  fetchFromGitHub,
  fetchCrate,
  runCommand,
}:

let
  rev = "f66f380c648551249df5ba8538983279ca800985";

  # The Rust crates meson would download, from this tree's own wraps.
  # Regenerate with update-wraps.py when moving rev.
  packageCache = runCommand "mesa-rust-package-cache" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatMapStrings (
      dep:
      let
        crate = fetchCrate {
          inherit (dep) pname version hash;
          unpack = false;
        };
      in
      ''
        ln -s ${crate} $out/${dep.pname}-${dep.version}.tar.gz
      ''
    ) (lib.importJSON ./wraps.json)
  );

  # nixpkgs builds every driver, so it enables these; without the drivers
  # they need, they are pointless or fail to configure.
  options = {
    # VA-API video: no driver built here has a video engine.
    gallium-va = "disabled";
    # These follow the d3d12 driver, for WSL.
    gallium-d3d12-video = "disabled";
    gallium-d3d12-graphics = "disabled";
    # TensorFlow Lite delegate for the NPU drivers.
    teflon = "false";
    # Ray tracing for Intel's Vulkan driver.
    intel-rt = "disabled";
    # Install the asahi tools only; panfrost's need its driver.
    tools = "asahi";
  };

  optionOf = flag: builtins.unsafeDiscardStringContext (lib.head (lib.splitString "=" flag));
  overridden = flag: lib.elem (optionOf flag) (map (name: "-D${name}") (lib.attrNames options));
in
(mesa.override {
  galliumDrivers = [
    "asahi"
    "llvmpipe"
  ];
  vulkanDrivers = [
    "asahi"
    "swrast"
  ];
  vulkanLayers = [
    "anti-lag"
    "device-select"
    "overlay"
    "screenshot"
    "vram-report-limit"
  ];
}).overrideAttrs
  (old: {
    version = "26.3.0-unstable-2026-11-11";

    src = fetchFromGitHub {
      owner = "GravityLinux";
      repo = "mesa";
      inherit rev;
      hash = "sha256-2T/Bdwzbmu0Y7nuguZ6JoRKvdBhvlxFLz7YYj6TELjg=";
    };

    # nixpkgs' opencl.patch, rebased: find clang's libraries where nixpkgs
    # keeps them, and leave the OpenCL ICD file to the package.
    patches = [ ./opencl.patch ];

    env = old.env // {
      MESON_PACKAGE_CACHE_DIR = packageCache;
    };

    mesonFlags =
      lib.filter (flag: !overridden flag) old.mesonFlags
      ++ lib.mapAttrsToList (name: value: "-D${name}=${value}") options;

    # spirv2dxil comes with the d3d12 drivers, so its output stays empty.
    postInstall = old.postInstall + ''
      mkdir -p $spirv2dxil
    '';

    meta = old.meta // {
      homepage = "https://github.com/GravityLinux/mesa";
      changelog = null;
      platforms = [ "aarch64-linux" ];
    };
  })

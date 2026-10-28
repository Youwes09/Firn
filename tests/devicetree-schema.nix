# Validate the J713 devicetree, and the bindings the series changes, against
# the kernel's dt-schema (make dtbs_check / dt_binding_check). Fails on any
# warning not listed below.
{
  pkgs,
  kernel,
}:
let
  inherit (pkgs) lib;
  patches = ../pkgs/linux/patches/topics;
  src = pkgs.applyPatches {
    name = "linux-j713-source";
    inherit (kernel) src;
    patches = map (name: patches + "/${name}") (lib.attrNames (builtins.readDir patches));
  };
  bindings = lib.concatStringsSep ":" [
    "apple,nvme-ans.yaml"
    "apple,dart.yaml"
    "apple,sart.yaml"
    "apple,spi.yaml"
    "apple,spmi.yaml"
    "apple,smc.yaml"
    "apple,pcie.yaml"
    "apple,dwc3.yaml"
    "apple,mailbox.yaml"
    "apple,admac.yaml"
    "apple,cluster-cpufreq.yaml"
    "apple,sio.yaml"
    "apple,spmi-nvmem.yaml"
  ];
  # Asahi's downstream drivers that have no binding on any Apple SoC yet, and
  # a warning in apple,pcie.yaml that predates this series.
  expected = pkgs.writeText "expected-warnings" ''
    Documentation/devicetree/bindings/pci/apple,pcie.yaml: ^pci@: Missing additionalProperties/unevaluatedProperties constraint
    /soc/aop@390c00000/als: failed to match any schema with compatible: ['apple,t8132-aop-als', 'apple,aop-als']
    /soc/aop@390c00000/audio: failed to match any schema with compatible: ['apple,t8132-aop-audio', 'apple,t6030-aop-audio']
    /soc/aop@390c00000: failed to match any schema with compatible: ['apple,t8132-aop', 'apple,t6020-aop']
    /soc/fifo@394b14000/input@8000: failed to match any schema with compatible: ['apple,t8132-dockchannel-hid', 'apple,dockchannel-hid']
    /soc/fifo@394b14000: failed to match any schema with compatible: ['apple,t8132-dockchannel', 'apple,dockchannel']
    /soc/gpu@302600000: failed to match any schema with compatible: ['apple,agx-t8132']
    /soc/mtp@394600000: failed to match any schema with compatible: ['apple,t8132-mtp', 'apple,t8132-rtk-helper-asc4', 'apple,mtp', 'apple,rtk-helper-asc4']
    /soc/mux@40304c000: failed to match any schema with compatible: ['apple,t8132-display-crossbar', 'apple,t8112-display-crossbar']
    /soc/mux@40b04c000: failed to match any schema with compatible: ['apple,t8132-display-crossbar', 'apple,t8112-display-crossbar']
    /soc/phy@403000000: failed to match any schema with compatible: ['apple,t8132-atcphy', 'apple,t8122-atcphy']
    /soc/phy@40b000000: failed to match any schema with compatible: ['apple,t8132-atcphy', 'apple,t8122-atcphy']
    /soc/sep@3aa600000: failed to match any schema with compatible: ['apple,t8132-sep', 'apple,sep']
  '';
in
pkgs.runCommandCC "firn-devicetree-schema"
  {
    nativeBuildInputs = with pkgs; [
      bison
      flex
      gnumake
      python3Packages.dtschema
      which
      yamllint
    ];
  }
  ''
    cp -r ${src} linux
    chmod -R u+w linux
    cd linux
    patchShebangs scripts >/dev/null
    cp ${kernel.configfile} .config
    make -s ARCH=arm64 olddefconfig >/dev/null
    {
      make -s ARCH=arm64 dt_binding_check DT_SCHEMA_FILES=${bindings} 2>&1
      make -s ARCH=arm64 CHECK_DTBS=y apple/t8132-j713.dtb 2>&1
    } | sed -e "s|$PWD/||g" -e 's|^arch/arm64/boot/dts/apple/t8132-j713.dtb: ||' \
      | grep -E '^(/soc|Documentation|t8132-j713|[a-z].*@[0-9a-f]+ \()' | sort -u > ../warnings
    if ! diff -u <(sort -u ${expected}) ../warnings; then
      echo "dt-schema reports warnings beyond the expected ones." >&2
      exit 1
    fi
    cp ../warnings $out
  ''

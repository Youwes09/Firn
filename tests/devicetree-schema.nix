# dtbs_check and dt_binding_check; fails on any warning not listed below.
{
  pkgs,
  kernel,
}:
let
  inherit (pkgs) lib;
  patches = ../pkgs/linux/patches;
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
  # Gravity's 7.3 T8132 devicetree against its bindings.
  expected = pkgs.writeText "expected-warnings" ''
    /soc/audio-controller: failed to match any schema with compatible: ['apple,t8132-dpaudio', 'apple,dpaudio']
    /soc/dcp@286e00000: failed to match any schema with compatible: ['apple,t8132-dcpext', 'apple,dcpext']
    /soc/dcp@30ae00000/panel: failed to match any schema with compatible: ['apple,panel-j713', 'apple,panel']
    /soc/dcp@30ae00000: failed to match any schema with compatible: ['apple,t8132-dcp', 'apple,dcp']
    /soc/dcp@48ae00000: failed to match any schema with compatible: ['apple,t8132-dcpext', 'apple,dcpext']
    /soc/display-subsystem: failed to match any schema with compatible: ['apple,display-subsystem']
    /soc/fifo@394b14000/input@0: failed to match any schema with compatible: ['apple,t8132-dockchannel-hid', 'apple,dockchannel-hid']
    /soc/fifo@394b14000: failed to match any schema with compatible: ['apple,t8132-dockchannel', 'apple,dockchannel']
    /soc/gpu@302600000: failed to match any schema with compatible: ['apple,agx-t8132']
    /soc/iommu@286300000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@286340000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@30a300000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@30a340000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@380300000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@390f00000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@394800000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@3ad060000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@402f00000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@402f80000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@40af00000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@40af80000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@412f00000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@412f80000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@41af00000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@41af80000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@48a300000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@48a340000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@490000000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@491000000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/iommu@492000000: failed to match any schema with compatible: ['apple,t8132-dart', 'apple,t8110-dart']
    /soc/mtp@394600000: failed to match any schema with compatible: ['apple,t8132-mtp', 'apple,t8132-rtk-helper-asc4', 'apple,mtp', 'apple,rtk-helper-asc4']
    /soc/phy@39a700000: failed to match any schema with compatible: ['apple,t8122-dptx-phy', 'apple,dptx-phy']
    /soc/phy@403000000: failed to match any schema with compatible: ['apple,t8132-atcphy', 'apple,t8122-atcphy']
    /soc/phy@40b000000: failed to match any schema with compatible: ['apple,t8132-atcphy', 'apple,t8122-atcphy']
    /soc/phy@413000000: failed to match any schema with compatible: ['apple,t8132-atcphy', 'apple,t8122-atcphy']
    /soc/phy@41b000000: failed to match any schema with compatible: ['apple,t8132-atcphy', 'apple,t8122-atcphy']
    /soc/pmp-report@3803c0000: failed to match any schema with compatible: ['apple,t8132-pmp-v2-report']
    /soc/pmp@380500000: failed to match any schema with compatible: ['apple,t8132-pmp-v2', 'apple,t6000-pmp-v2']
    framebuffer@0 (apple,simple-framebuffer): 'post-init-providers' does not match any of the regexes: '^[a-zA-Z0-9-]+-supply$', '^pinctrl-[0-9]+$'
    i2s@393600000 (apple,t8132-mca): clocks: [[85], [85], [85]] is too long
    i2s@393600000 (apple,t8132-mca): dma-names: ['tx0a', 'tx1a', 'tx2a'] is too long
    i2s@393600000 (apple,t8132-mca): dma-names:1: 'rx0a' was expected
    i2s@393600000 (apple,t8132-mca): dma-names:2: 'tx0b' was expected
    i2s@393600000 (apple,t8132-mca): dmas: [[89, 0], [89, 2], [89, 4]] is too long
    i2s@393600000 (apple,t8132-mca): power-domains: [[84], [86], [87], [88]] is too long
    iommu@286300000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@286340000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@30a300000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@30a340000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@380300000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@390f00000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@394800000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@3ad060000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@402f00000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@402f80000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@40af00000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@40af80000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@412f00000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@412f80000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@41af00000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@41af80000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@48a300000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@48a340000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@490000000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@491000000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    iommu@492000000 (apple,t8132-dart): compatible: 'oneOf' conditional failed, one must be fixed:
    mailbox@380e08000 (apple,t8103-asc-mailbox): power-domains: [[18], [19]] is too long
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
    # Linux 7.3 gives ti,irqs-reserved two types in these TI bindings, and
    # dtschema crashes reporting it; neither concerns an Apple devicetree.
    rm Documentation/devicetree/bindings/interrupt-controller/ti,{pruss-intc,irq-crossbar}.yaml
    if ! {
      make -s ARCH=arm64 dt_binding_check DT_SCHEMA_FILES=${bindings}
      make -s ARCH=arm64 CHECK_DTBS=y apple/t8132-j713.dtb
    } > ../output 2>&1; then
      cat ../output >&2
      exit 1
    fi
    sed -e "s|$PWD/||g" -e 's|^arch/arm64/boot/dts/apple/t8132-j713.dtb: ||' ../output \
      | grep -E '^(/soc|Documentation|t8132-j713|[a-z].*@[0-9a-f]+ \()' | sort -u > ../warnings
    if ! diff -u <(sort -u ${expected}) ../warnings; then
      echo "dt-schema reports warnings beyond the expected ones." >&2
      exit 1
    fi
    cp ../warnings $out
  ''

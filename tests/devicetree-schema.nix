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
    "apple,atcphy.yaml"
    "apple,pmp.yaml"
    "apple,pmp-report.yaml"
    "ti,tps6598x.yaml"
  ];
  # Nodes whose bindings are not written yet (docs/TODO.md).
  expected = pkgs.writeText "expected-warnings" ''
    /soc/dcp@30ae00000/panel: failed to match any schema with compatible: ['apple,panel-j713', 'apple,panel']
    /soc/dcp@30ae00000: failed to match any schema with compatible: ['apple,t8132-dcp', 'apple,dcp']
    /soc/fifo@394b14000: failed to match any schema with compatible: ['apple,t8132-dockchannel', 'apple,dockchannel']
    /soc/fifo@394b14000/input@0: failed to match any schema with compatible: ['apple,t8132-dockchannel-hid', 'apple,dockchannel-hid']
    /soc/mtp@394600000: failed to match any schema with compatible: ['apple,t8132-mtp', 'apple,t8132-rtk-helper-asc4', 'apple,mtp', 'apple,rtk-helper-asc4']
    /soc/phy@39a700000: failed to match any schema with compatible: ['apple,t8132-dptx-phy', 'apple,dptx-phy']
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

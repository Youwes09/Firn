# Boots what the installer would write in QEMU; tests software, not hardware.
{ pkgs, nixos }:
let
  test = nixos.extendModules { modules = [ ./selftest.nix ]; };
  cfg = test.config;
  toplevel = cfg.system.build.toplevel;
  installer = pkgs.callPackage ../../pkgs/installer/source.nix { };
  rootImage = pkgs.callPackage "${toString nixos.pkgs.path}/nixos/lib/make-ext4-fs.nix" {
    storePaths = [ toplevel ];
    volumeLabel = cfg.hardware.firn.image.label;
    uuid = cfg.hardware.firn.image.rootUuid;
  };
  efiUuid = "3d6b3c0e-5f1a-4a8e-9b7d-2c4e6f8a0b1c";
  machine = "-M virt -cpu max -smp 2 -m 3072";
in
pkgs.runCommand "firn-vm-boot"
  {
    nativeBuildInputs = with pkgs; [
      python3
      qemu
      dtc
      dosfstools
      mtools
      util-linux
      coreutils
      gnugrep
    ];
    passthru = { inherit toplevel rootImage; };
  }
  ''
    python3 -I ${./prepare.py} \
      --payloads ${installer}/src/payloads.py \
      --firn-boot ${../../pkgs/firn-boot/firn-boot.py} \
      --toplevel ${toplevel} \
      --out parts

    cp ${rootImage} root.img
    chmod u+w root.img
    truncate -s +1G root.img

    truncate -s 72M esp.img
    sfdisk --quiet esp.img <<EOF
    label: gpt
    start=2048, size=143360, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=${efiUuid}
    EOF
    mkfs.vfat -C fat.img 71680 >/dev/null
    export MTOOLS_SKIP_CHECK=1
    mmd -i fat.img ::/m1n1
    mcopy -i fat.img parts/boot.bin ::/m1n1/boot.bin
    mmd -i fat.img ::/asahi ::/vendorfw
    echo firn-test-installer-data > installer.log
    mcopy -i fat.img installer.log ::/asahi/installer.log
    mcopy -i fat.img installer.log ::/vendorfw/manifest.txt
    dd if=fat.img of=esp.img bs=512 seek=2048 conv=notrunc status=none

    qemu-system-aarch64 ${machine} -machine dumpdtb=virt.dtb -nographic >/dev/null
    fdtput -t s virt.dtb /chosen asahi,efi-system-partition ${efiUuid}

    timeout 3000 qemu-system-aarch64 ${machine} -nographic -no-reboot \
      -dtb virt.dtb \
      -kernel ${toplevel}/kernel \
      -initrd parts/initramfs.img \
      -append "$(cat parts/bootargs.txt) console=ttyAMA0" \
      -drive file=root.img,format=raw,if=virtio \
      -drive file=esp.img,format=raw,if=virtio \
      -nic none > serial.log 2>&1 || true

    mkdir $out
    cp serial.log $out/serial.log
    grep 'FIRN-SELFTEST' serial.log | tee $out/results.txt
    grep -q 'FIRN-SELFTEST DONE result=PASS' serial.log || {
      echo "VM self-test did not pass; last console lines:" >&2
      tail -60 serial.log >&2
      exit 1
    }
  ''

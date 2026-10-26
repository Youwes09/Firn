# T2: boot the shipped kernel and initrd in QEMU's generic arm64 machine, from
# what the installer would write, and run the self-test inside. This checks the
# software path (first boot, firmware hand-off, EFI mount, m4-nix-boot), not
# Apple hardware: QEMU's devicetree describes a virtual machine, not the Air.
{ pkgs, nixos }:
let
  inherit (pkgs) lib;
  test = nixos.extendModules { modules = [ ./selftest.nix ]; };
  cfg = test.config;
  toplevel = cfg.system.build.toplevel;
  sources = pkgs.callPackage ../../pkgs/sources.nix { };
  rootImage = pkgs.callPackage "${toString nixos.pkgs.path}/nixos/lib/make-ext4-fs.nix" {
    storePaths = [ toplevel ];
    volumeLabel = cfg.hardware.m4-j713.image.label;
    uuid = cfg.hardware.m4-j713.image.rootUuid;
  };
  # The EFI partition's GPT UUID, which m1n1 stage 1 passes in the devicetree.
  efiUuid = "3d6b3c0e-5f1a-4a8e-9b7d-2c4e6f8a0b1c";
  machine = "-M virt -cpu max -smp 2 -m 3072";
in
pkgs.runCommand "m4-nix-vm-boot"
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
      --installer-bundle ${sources.installerKit}/installer-macos.tar.gz \
      --nix-boot ${../../pkgs/m4-nix-boot/m4-nix-boot.py} \
      --loader ${sources.loader} \
      --toplevel ${toplevel} \
      --out parts

    # Root: the image on a larger disk, as the installer's expanded partition.
    cp ${rootImage} root.img
    chmod u+w root.img
    truncate -s +1G root.img

    # EFI system partition holding the installer's boot.bin.
    truncate -s 72M esp.img
    sfdisk --quiet esp.img <<EOF
    label: gpt
    start=2048, size=143360, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=${efiUuid}
    EOF
    mkfs.vfat -C fat.img 71680 >/dev/null
    export MTOOLS_SKIP_CHECK=1
    mmd -i fat.img ::/omarchy
    mcopy -i fat.img parts/boot.bin ::/omarchy/boot.bin
    dd if=fat.img of=esp.img bs=512 seek=2048 conv=notrunc status=none

    # QEMU's own devicetree plus the property m1n1 stage 1 sets.
    qemu-system-aarch64 ${machine} -machine dumpdtb=virt.dtb -nographic >/dev/null
    fdtput -t s virt.dtb /chosen gravity,efi-system-partition ${efiUuid}

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
    grep 'M4-NIX-SELFTEST' serial.log | tee $out/results.txt
    grep -q 'M4-NIX-SELFTEST DONE result=PASS' serial.log || {
      echo "VM self-test did not pass; last console lines:" >&2
      tail -60 serial.log >&2
      exit 1
    }
  ''

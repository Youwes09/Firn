# The devicetree built from source must match Omarchy-M4-Native's release
# binary, which has booted on the J713, except for these reviewed differences.
{
  pkgs,
  kernel,
  releaseDtb,
}:
let
  expected = pkgs.writeText "expected-differences" ''
    only in A: /soc/avd@3a0000000
    only in B: /soc/dma-controller@3ade00000
    /soc/fifo@394b14000/input@8000: compatible
    only in A: /soc/gpu-real-id-observer@300d04000
    /soc/gpu@302600000: mboxes
    only in A: /soc/iommu@3a1020000
    only in A: /soc/mailbox@302608000
    only in B: /soc/mbox@302608000
    /soc/mbox@38c608000: interrupts
    /soc/mbox@390608000: interrupts
    /soc/mbox@394608000: interrupts
    /soc/mbox@3aa608000: interrupts
    /soc/mbox@3ade08000: interrupts
    /soc/nvme@4c5cc0000: reg
    /soc/nvme@4c5cc0000: reg-names
    only in A: /soc/sio@3ade00000
    /soc/usb@402280000: iommus
  '';
  # Why each one differs:
  #   SMC, AOP, MTP, SEP and SIO mailboxes: interrupts in binding order; the
  #     release swaps the send pair (SMC, MTP) or both pairs.
  #   NVMe: no "nvmmu" window; the driver reaches the NVMMU through "nvme".
  #   GPU mailbox: named mbox@ like every other mailbox, hence also the
  #     GPU's mboxes reference.
  #   Front USB-C controller (disabled on J713): stream IDs <0>, <1>.
  #   SIO: named dma-controller@ as its binding requires.
  #   Keyboard and trackpad: the t8132 compatible selects the version 2
  #     interface reset that the multi-touch firmware needs.
  #   AVD, its DART and the GPU ID observer: not described until used.
in
pkgs.runCommand "m4-nix-devicetree" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 -I ${./dtcmp.py} ${releaseDtb} ${kernel}/dtbs/apple/t8132-j713.dtb > actual
  if ! diff -u ${expected} actual; then
    echo "The source devicetree differs from the release one in unreviewed ways." >&2
    exit 1
  fi
  cp actual $out
''

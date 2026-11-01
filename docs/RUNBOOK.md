# Firn runbook

Test tiers, in order. Do not go on past a failed gate.

| Tier | Where | Command | Gate |
|---|---|---|---|
| T0 unit tests | PC | `nix build .#checks.x86_64-linux.firn-boot` | All tests pass, including the contract tests against the installer's payloads.py |
| T1 policy | PC | `nix build .#checks.x86_64-linux.policy` | Every rule `ok` |
| T2 VM boot | PC | `nix build .#checks.x86_64-linux.vm-boot` | `FIRN-SELFTEST DONE result=PASS` |
| Kit | PC | `nix build .#packages.x86_64-linux.kit` | Builds; `BUILD-REPORT.json` lists the installer's own checks |
| T3 preflight | Mac, read-only | `bash preflight.command` | `RESULT: ready to install`, or WARN lines understood |
| T4 install | Mac | [GUIDE.md](GUIDE.md), parts 4 and 5 | Each stage's checks |

T2 boots the shipped initrd in QEMU's virtual arm64 machine, on the J713 kernel
plus the drivers that machine needs (`pkgs/linux/qemu-virt.config`). It tests
the software path, not Apple hardware. Its EFI partition is on a separate
virtual disk, so it cannot catch anything that depends on the Mac's single
disk layout, such as systemd's GPT auto-mounting.

Updating an installed Air: `sudo nixos-rebuild boot --flake .#minimal`, then
`sudo ls -l /boot/efi/m1n1/` should show `boot.bin` and `boot.bin.original`,
and from the second update on `boot.bin.previous`, before you reboot. If the
new generation does not boot, GUIDE.md's R1 restores one of them from macOS.

The EFI partition is 500 MB and each boot.bin about 105 MB, so it holds only
`m1n1/`: the installer's `asahi/` and `vendorfw/`, which Firn does not read,
are moved to `/var/lib/firn/installer/` at boot and before each update.

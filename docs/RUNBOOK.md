# M4-Nix runbook

Test tiers, in order. Do not go on past a failed gate.

| Tier | Where | Command | Gate |
|---|---|---|---|
| T0 unit tests | PC | `nix build .#checks.x86_64-linux.m4-nix-boot` | All tests pass, including the installer contract tests |
| T1 policy | PC | `nix build .#checks.x86_64-linux.policy` | Every rule `ok` |
| T2 VM boot | PC | `nix build .#checks.x86_64-linux.vm-boot` | `M4-NIX-SELFTEST DONE result=PASS` |
| Kit | PC | `nix build .#packages.x86_64-linux.kit` | Builds; `BUILD-REPORT.json` lists the installer checks |
| T3 preflight | Mac, read-only | `bash preflight.command` | `RESULT: ready to install`, or WARN lines understood |
| T4 install | Mac | [GUIDE.md](GUIDE.md), parts 4 and 5 | Each stage's checks |

T2 boots the shipped kernel and initrd in QEMU's virtual arm64 machine. It tests
the software path, not Apple hardware. Its EFI partition is on a separate
virtual disk, so it cannot catch anything that depends on the Mac's single
disk layout, such as systemd's GPT auto-mounting.

Updating an installed Air: `sudo nixos-rebuild boot --flake .#minimal`, then
`sudo ls -l /boot/efi/omarchy/` should show `boot.bin`, `boot.bin.original` and
`boot.bin.previous` before you reboot. If the new generation does not boot,
GUIDE.md's R1 restores `boot.bin.previous` from macOS.

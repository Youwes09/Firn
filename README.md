# M4-Nix

NixOS on the 13-inch M4 MacBook Air (Mac16,12 / J713). Experimental and
unofficial; installed and booting on one Air.

The kernel is Asahi Linux's `asahi-7.1.9-1` with a series of J713 patches,
built from source. The installer comes from
[Omarchy-M4-Native](https://github.com/Kb2uka/Omarchy-M4-Native)'s alpha.1
release, and by default so do the m1n1 stage 2 loader and the devicetree.
Both also build from source (`hardware.m4-j713.loader` and
`hardware.m4-j713.devicetree`), which becomes the default once it has booted
([docs/ISSUES.md](docs/ISSUES.md)).

## What works

Keyboard, NVMe, Wi-Fi, hinge-side USB-C and the simpledrm console. Set
`hardware.m4-j713.wifiRegion` (for example `"US"`) for 5 GHz Wi-Fi.

Not supported: the trackpad, speakers, headphones, GPU, CPU idle states,
clocks above iBoot's handover, backlight control, the front USB-C port,
suspend. Closing the lid powers off. Sustained writes of several GB can crash
the storage controller; see [docs/ISSUES.md](docs/ISSUES.md).

## Layout

| Path | What |
|---|---|
| `modules/` | The NixOS module: kernel, boot, firmware, power, root image |
| `pkgs/linux/` | The kernel and devicetree: configuration, patch series, module list |
| `pkgs/m1n1/` | m1n1 stage 2 built from source |
| `pkgs/mesa/` | Mesa for the M4 GPU (not yet used) |
| `pkgs/m4-nix-boot/` | Writes each generation into `boot.bin`, with tests |
| `pkgs/kit/` | The installer kit |
| `pkgs/sources.nix` | Downloads pinned from Omarchy-M4-Native's release |
| `tests/` | Policy checks, kernel module list, devicetree comparison, VM boot |
| `examples/minimal/` | A console-only system |

## Booting

The installer writes `<ESP>/omarchy/boot.bin`: m1n1 stage 2, kernel
parameters, kernel, devicetree, initrd and the Apple firmware it collected.
Every `nixos-rebuild boot|switch` runs
[`m4-nix-boot`](pkgs/m4-nix-boot/m4-nix-boot.py), which writes the
generation's kernel, devicetree, initrd and parameters in the same layout and
keeps the loader and firmware. It refuses an unknown loader or devicetree,
parameters without `maxcpus=10 idle=nop arm64.nowfxt`, and any board but J713.
The installer's file is kept as `boot.bin.original`, the last one as
`boot.bin.previous`.

## Building

The kernel and m1n1 cross-compile on x86_64:

```
nix build .#packages.x86_64-linux.linux
nix build .#checks.x86_64-linux.policy .#checks.x86_64-linux.kernel-modules
```

The rest of the system needs an aarch64 builder, or
`boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` on the build machine.
[docs/RUNBOOK.md](docs/RUNBOOK.md) lists the test tiers;
[docs/GUIDE.md](docs/GUIDE.md) is the install guide, also shipped in the kit.
Machine-local settings such as SSH keys go in `examples/minimal/access.nix`,
which is gitignored and imported when present.

## Provenance

The kernel patches keep their authors: upstream patches as posted, and
Omarchy-M4-Native's changes credited to KB2UKA. The installer bundle,
m1n1 stage 2 and devicetree are downloaded unmodified from Omarchy-M4-Native's
releases (MIT for the installer and m1n1, GPL-2.0-only for the devicetree);
the installer's notices ship in the kit. `Install.command` is adapted from
theirs (MIT, © studioxradio aka kb2uka). This project is not affiliated with or
endorsed by Omarchy-M4-Native, Omarchy, Asahi Linux or Apple.

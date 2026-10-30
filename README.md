# Firn

NixOS on the 13-inch M4 MacBook Air (Mac16,12 / J713). Experimental and
unofficial.

Everything that runs on the Air is built from source here:

- the kernel: Gravity Linux's `gravity-m4` (7.1.13) with the J713 patches
  it lacks;
- m1n1 stage 1 and stage 2: upstream m1n1 with Firn's patches;
- the macOS-side installer: Gravity Linux's installer with the J713 added.

The installer runs under python.org's Python for macOS and Homebrew's libffi,
both pinned by hash, as Asahi Linux's own installer does.

## What works

Keyboard, trackpad, NVMe, Wi-Fi, Bluetooth, hinge-side USB-C and the panel,
with brightness in `/sys/class/backlight/apple-panel-bl`. Set
`hardware.firn.wifiRegion` (for example `"US"`) for 5 GHz Wi-Fi.

Not supported: speakers, headphones, GPU, CPU clocks above the heat caps,
the front USB-C port, suspend. Closing the lid powers off. Sustained writes of
several GB can crash the storage controller; see
[docs/ISSUES.md](docs/ISSUES.md).

## Layout

| Path | What |
|---|---|
| `modules/` | The NixOS module: kernel, boot, firmware, power, root image |
| `pkgs/linux/` | The kernel and devicetree: configuration, patch series, module list |
| `pkgs/m1n1/` | m1n1 stage 1 and stage 2 |
| `pkgs/installer/` | The macOS-side installer |
| `pkgs/firn-boot/` | Writes each generation into `boot.bin`, with tests |
| `pkgs/firn-report/` | A read-only hardware report |
| `pkgs/kit/` | The installer kit: installer, OS package and guide |
| `tests/` | Policy checks, kernel module list, devicetree schema, VM boot |
| `examples/minimal/` | A console-only system |

## Booting

The installer registers m1n1 stage 1 in a small macOS stub, which loads
`<ESP>/m1n1/boot.bin`: m1n1 stage 2, kernel parameters, kernel, devicetree,
and an initrd with the Apple firmware the installer collected. Every
`nixos-rebuild boot|switch` runs [`firn-boot`](pkgs/firn-boot/firn-boot.py),
which writes the generation's m1n1, kernel, devicetree, initrd and parameters
in the same layout and keeps the firmware. It refuses parameters without
`maxcpus=10 idle=nop arm64.nowfxt`, and any board but J713. The installer's
file is kept as `boot.bin.original`, the last one as `boot.bin.previous`.
The installer's other files on that partition move to
`/var/lib/firn/installer/`, to leave room for them.

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
which is gitignored and imported when present. A flake reference to the
git tree leaves untracked files out, so build the system with
`path:.#minimal` to include it.

## Provenance

Patches keep their authors. Upstream kernel patches are as posted, and
changes from [Omarchy-M4-Native](https://github.com/Kb2uka/Omarchy-M4-Native)
are credited to KB2UKA, in the kernel series and in m1n1's patches.
The installer patches credit the Gravity Linux installer, as shipped by
Omarchy-M4-Native, where they follow it. The installer kit ships the
licence notices of everything in the installer. The logo
([artwork/firn-logo.png](artwork/firn-logo.png)) is derived from Gravity
Linux's.

## Licence

Firn's own code is under the [MIT licence](LICENSE). Patches keep the
licence of the project they apply to or the one their author chose: the
kernel's are GPL-2.0, and m1n1's t8132 GPU handoff is GPL-2.0-or-later.

Firn is not affiliated with or endorsed by Asahi Linux, Omarchy-M4-Native,
Gravity Linux or Apple.

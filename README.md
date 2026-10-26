# M4-Nix

NixOS on the 13-inch M4 MacBook Air (Mac16,12 / J713), using the hardware
work of [Omarchy-M4-Native](https://github.com/Kb2uka/Omarchy-M4-Native)
without its desktop. NixOS is installed directly by that project's macOS-side
installer, with a NixOS OS package in place of Omarchy's. Experimental and
unofficial; installed and booting on one Air.

## Minimal-risk profile

`hardware.m4-j713.enable = true` turns on only what the Air needs to run:

| On | Source |
|---|---|
| Kernel `7.1.9-m4-gpu-backport-20261008` | Their published prebuilt Image.gz and modules, hash-pinned, not rebuilt |
| Kernel parameters | Exactly the hardware switches their update 4 installer ships |
| Devicetree `j713-cputemp` | Poweroff fix, CPU clocks capped at iBoot's handover (P ≤ 1800 MHz, E 900 MHz), reporting-only temperatures |
| NVMe, keyboard, trackpad, Wi-Fi, hinge-side USB-C, simpledrm display | Kernel and devicetree above |

Set `hardware.m4-j713.wifiRegion` (for example `"US"`) for 5 GHz Wi-Fi; without
it the kernel stays in the world region. Also enforced: no suspend or hibernate, lid close powers off, and the speaker
and headphone codec drivers are blacklisted. These options exist but **refuse
to evaluate** until ported: `speakers`, `headphones`, `gpu`, `cpuIdle`,
`cpuBoost`, `backlight`, `frontUsb`, `notch`.

## How it installs and boots

The installer kit (`nix build .#packages.x86_64-linux.kit`) is their update 4
installer bundle, unchanged and hash-pinned, plus:

- `os/nixos-j713.zip`: the NixOS root image and the boot parts (their m1n1
  stage 2 loader, the pinned kernel and devicetree, the NixOS initrd);
- `installer_data.json`: their entry with our package, root UUID and boot
  arguments;
- `Install.command` (theirs, without the Widevine question) and
  `preflight.command` (read-only checks).

The kit build validates the package with the installer's own code
(`OSInstaller` root checks and `m4boot.read_parts`). The installer collects the
Apple firmware on the Mac and writes `<ESP>/omarchy/boot.bin`.

After that, every `nixos-rebuild boot|switch` runs
[`m4-nix-boot`](pkgs/m4-nix-boot/m4-nix-boot.py), which rewrites `boot.bin`
in the installer's exact layout: same loader and firmware, the generation's
kernel, devicetree, initrd and parameters. It refuses unpinned parts, a
parameter set without the qualified switches, and any board but J713. The
installer's file is kept as `boot.bin.original`, the last one as
`boot.bin.previous`.

## Testing

[docs/RUNBOOK.md](docs/RUNBOOK.md) lists the test tiers: unit and
installer-contract tests, policy checks on the evaluated system, and a QEMU
boot of the shipped kernel and initrd with a self-test.
[docs/GUIDE.md](docs/GUIDE.md) is the install guide, also shipped in the kit:
preparing the Mac, installing, first-boot checks and recovery.

Machine-local settings such as SSH keys go in `examples/minimal/access.nix`,
which is gitignored and imported when present.

Building the system on x86_64 needs `boot.binfmt.emulatedSystems =
[ "aarch64-linux" ]`; most of it comes from the binary cache.

## Layout

| Path | What |
|---|---|
| `modules/j713.nix`, `modules/image.nix` | The NixOS module: profile, boot, first boot, EFI mount |
| `pkgs/linux-m4.nix`, `pkgs/kernel.config` | The prebuilt kernel as a NixOS kernel |
| `pkgs/sources.nix` | Every pinned download, including ranged fetches from their release |
| `pkgs/m4-nix-boot/` | boot.bin writer and its tests |
| `pkgs/m4-nix-report/` | Read-only hardware report for the runbook |
| `pkgs/kit/` | Installer kit assembly and validation |
| `tests/` | Policy checks and the VM boot test |

## Provenance

The kernel, modules, devicetree, m1n1 stage 2 and installer bundle are
downloaded unmodified from Omarchy-M4-Native's releases (GPL-2.0-only for the
kernel, MIT for the installer and m1n1; sources are in that project's release
archives, and the installer's notices ship in the kit). `pkgs/kernel.config`
is that kernel's configuration. `Install.command` is adapted from theirs (MIT,
© studioxradio aka kb2uka). This project is not affiliated with or endorsed by
Omarchy-M4-Native, Omarchy, Asahi Linux or Apple.

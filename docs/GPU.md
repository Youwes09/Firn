# GPU support plan (t8132, G16)

The goal is M4 GPU support written as part of Asahi Linux's GPU driver
(`drivers/gpu/drm/asahi`), in the form that driver uses for every other
generation, so that it could be reviewed there. Working code that sits beside
the driver is a means to that end, not the end.

## Where Asahi's driver stands

The driver supports G13 (M1) and G14 (M1 Pro/Max/Ultra, M2) with firmware
from macOS 12.3 to 13.5. Two things select the code for a machine:

- the GPU generation, `GpuGen` in `hw/mod.rs` (part of the UABI), with one
  `HwConfig` per SoC in `hw/` (`t8103.rs`, `t8112.rs`, `t600x.rs`,
  `t602x.rs`);
- the firmware ABI version, from the `versions` macro in
  `rust/macros/versions.rs`: `G13`, `G14`, `G14X` against `V12_3` …
  `V13_5`. Firmware structures in `fw/` and the code using them carry
  `#[versions(AGX)]` and `#[ver(V >= …)]`, and `driver.rs` instantiates one
  `GpuManager` per supported pair.

There is no G15 (M3) support and no firmware ABI newer than macOS 13.5.

## What the M4 needs

- A new generation, G16 (`gpu,t8132` in the ADT).
- A new firmware ABI. Linux runs the GPU firmware of the boot stub, which
  the installer builds from macOS 26.5.1: `mBoot-18000.120.36`. Its
  structures differ from 13.5 in ways the reference implementation
  documents. The reference's firmware data maps onto Asahi's structures:
  its root block is `InitData` field for field, and its main block is
  `RuntimePointers` with the same 17 channels, each now 0x20 bytes.
- A 42-bit GPU address space, with the firmware's kernel range at
  `0xffff_fc00_0000_0000`, per the reference's code (its comments say 43).
  The page-table entry format is Asahi's unchanged. The reference also
  cleans page tables from the CPU cache before the GPU reads them. Both are
  unconfirmed until the firmware runs: on the J713, iBoot reserves the UAT
  regions but leaves them empty, and m1n1 does not set up the GPU.

## The reference implementation

Omarchy-M4-Native's installer kernel carries about 9,500 lines of G16 support
(`g16*.rs`, `m4_*.rs`, `asahi_m4.rs`) from GravityLinux (© The Gravity Linux
Contributors, GPL-2.0-only), "adapted from Niklas Sheth's
linux-m4-integration prototype" and "ported from the working Python DRM
shim". It runs on the Air, but:

- it is a separate driver inside the directory: it uses none of Asahi's
  `hw`, `fw`, `queue`, `mmu` or `alloc` modules, and duplicates the page
  tables (`m4_pgtable.rs`), VM, firmware bootstrap, queues and power
  management;
- it accepts firmware `mBoot-18000.161.10`, and `mBoot-18000.120.36` on
  the J713 with `air_bootstrap_test=1`; both use the same structures;
- it carries bring-up scaffolding: about 50 `unsafe` blocks, 26 info and
  warning prints, and benchmark, qualification and tracing code;
- it changes the UAPI (`include/uapi/drm/asahi_drm.h`), which its Mesa
  fork follows;
- it is very likely LLM-assisted, so every line it informs is read and
  understood, not copied.

It is used as a reference for the G16 hardware and firmware behaviour, and
as a known-working baseline to test against. Code here is written fresh in
Asahi's structure; facts taken from the reference are credited in the
commit messages.

## Milestones

Each milestone is one or more patches that build, keep G13/G14 unchanged,
and are tested on the J713 where they can be.

0. **Baseline.** Boot the reference unmodified, outside the series, with its
   Mesa: confirm the GPU works on this Air and fix the test programs
   (`kmscube`, a Vulkan cube, `glmark2-es2-drm`). Nothing from it is kept.
1. **Identity.** `GpuGen::G16`, the firmware ABI version in the `versions`
   macro, and `hw/t8132.rs` with the configuration read from the ADT and the
   reference. The driver probes, recognises the GPU and stops before
   starting firmware.
2. **Memory.** The input address width as a page-table parameter, so
   `pgtable.rs` serves the 39-bit G13/G14 layout and G16's wider one.
   The G16 layout in `mmu.rs` and page-table cache cleaning come with
   milestone 3, where the firmware can confirm them.
3. **Firmware start.** The macOS 26 `initdata` layout in `fw/initdata.rs`
   and `initdata.rs`; the firmware boots and answers.
4. **Channels and events.** `fw/channels.rs`, `fw/event.rs`,
   `workqueue.rs` for the new ABI; the firmware processes no-op work.
5. **Jobs.** Vertex, fragment and compute (`fw/vertex.rs`,
   `fw/fragment.rs`, `fw/compute.rs`) and the queue code; `kmscube` runs.
6. **Power.** Performance states and power management through the existing
   paths.
7. **UAPI and Mesa.** Keep Asahi's UAPI if the hardware allows, otherwise
   extend it the way Asahi versions it, and package a matching Mesa.

## Rules for this work

- Asahi's structure first: a change that needs a parallel copy of an
  existing module is redesigned instead.
- No Apple code: no firmware or macOS disassembly. Structures and
  sequences come from the reference, from observing the hardware, and from
  the firmware's own reports.
- Patches are small and each says what it changes and why. Origin of every
  non-obvious fact is credited.
- Asahi does not accept LLM-assisted contributions
  (<https://asahilinux.org/llm-policy/>). This work is LLM-assisted and says
  so; it is written to their standard so that a human could re-implement it
  from the documentation if they wanted it upstream.

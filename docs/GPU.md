# GPU (T8132, G16)

Not supported yet. The kernel series has no GPU driver, and the policy check
makes sure none is built.

The driver is being ported on its own branch, `firn/gpu-next` (in
`~/Universal/M4-Nix/src/firn-gpu`): Cody Ho's and Niklas Sheth's `asahi_m4`
history on Firn's kernel, moved to mainline's dma_fence and to an RTKit
registration the device owns. With Gravity Linux's Mesa it renders OpenGL ES
and Vulkan on the J713, on the internal display too, with PMP running (see
"Rendering" below). `firn/gpu` is the earlier, firmware-only state.

## Measured on the J713

- `ID_VERSION` `0x0a021100`: G16, variant G, revision B1.
- `CORE_MASK` `0x3bd`: cores 1 and 6 fused off.
- ADT `/arm-io/sgx`: `gpu,t8132`, 16 performance states up to 1470 MHz.
- iBoot reserves the UAT regions at `0x103fff70000` but leaves them empty;
  the driver has to build the tables.

## What a driver needs on the J713

- **Firmware `mBoot-18000.161.10`** (macOS 26.6.x). The installer puts a
  macOS 26.6.2 stub beside macOS, which provides it.
- **Ten performance states.** Gravity Linux's `asahi_m4` driver, in its
  `gravity-m4` kernel, read exactly eleven; the driver now takes a ladder of
  any length.
- **m1n1's GPU handoff**, in Gravity Linux's bootloader: the memory regions,
  firmware build, core mask and performance tables. When it fails, stage 2
  boots without the GPU instead of stopping. The J713 needs Niklas's
  per-board calibration (stage 2 patches 0012 to 0017); without it m1n1
  leaves the GPU node disabled.

## First runs (2026-11-13)

Logs: `~/Universal/M4-Nix/gpu/firn-gpu-runs/`.

- m1n1 hands the GPU over: the node is `okay`, with `mBoot-18000.161.10`,
  core mask `0x3bd`, 1470 MHz and a 26250 mW limit. `probe_only=1` validates
  all five memory regions.
- On a full load the firmware boots, accepts the initialization graph, and
  DRM registers `card0` and `renderD128`. About 7 ms later the firmware
  crashes:
  `agfMTRAlarmHandler: Received MTR Alarm interrupt from GPU but no match
  found in MTR hardware! chainID=0`. It does this every time, with or
  without the dma_fence and RTKit rework.
- **The trigger is PMP.** With `pmp` blacklisted, the firmware runs with no
  crash. Starting PMP afterwards crashes it 8 ms after PMP logs "PMP started".
  Niklas's Mac mini setup never starts PMP, which is why it never showed up
  there.
- Ruled out: SAPT. m1n1 recorded the table before Niklas's
  `sapt_disable()` cleared it, and it was all zero, so clearing it changes
  nothing on the J713.
- **Within PMP, it is the GPU's LTS loop.** Bisected with a debug-only
  patch to the PMP driver (`pmp-bisect/` in the logs). Each run loads the
  GPU, then PMP:

  | PMP change | GPU firmware |
  |---|---|
  | none | crashes 8-12 ms after "PMP started" |
  | `agx-monitor` = 0 | crashes |
  | die temperature alarm0 and alarm1 disabled | crashes |
  | MTR_TOP_AGX left out of `temp-sensor` | crashes |
  | fast-die tunables withheld | crashes |
  | AGX bandwidth tunables withheld | crashes |
  | all six `lts-*` tunables withheld | runs |
  | `lts-ctrl-ts` and `lts-ctrl-loop` withheld | runs |
  | `lts-config` and `lts-voltage` withheld | runs |
  | only the `GPU` entry of `lts-ctrl-loop` removed | runs |

- What the ADT says (`/arm-io/pmp/iop-pmp-nub`): `lts-ctrl-loop` has two
  loops of 0x70 bytes, `PACC` on sensors 4-6 (Tp000m-Tp002m) and `GPU` on
  sensor 7. `temp-sensor` entry 7 is `MTR_TOP_AGX`, at 109 °C, so MTR is
  the GPU's own die temperature sensor block. `lts-voltage` covers EACC,
  PACC, ANE and AGX. `lts-config` holds 110 and 105 °C points. LTS looks like
  a temperature-dependent voltage limit for chip lifetime (there is also an
  `lts-acsk-tddb-config`, empty on the J713).
- PMP fills the per-sensor values itself from `temp-sensor`
  (`mtr_top_agx-alarm1-temp` is 0x6d0000, 109.0 °C in 16.16), so Firn's
  PMP driver is not handing it bad numbers.
- macOS runs the same GPU loop, so on macOS the GPU firmware is set up to
  accept that loop's MTR alarms. The G16 driver builds its firmware data
  from zeroed buffers and fills only the fields it knows, so the setting
  macOS uses for this was missing (fixed below).

### Fix: the MTR sensor mask

Niklas Sheth sent macOS 26.6.2's initialization data from a J713, read
with macOS paused after boot (`~/Universal/M4-Nix/gpu/niklas-postinit-20261110/`).
It was diffed word by word against our driver's
(`firn-gpu-runs/initdata-diff/`). A debug patch on `debug/initdata`
loads a list of values from a file before the firmware starts and keeps
a copy of what the driver handed over, so value sets can be swapped
between reboots without rebuilding. Words our own firmware changed after
boot are its state and were left out; the voltage tables are each chip's
calibration; everything above bundle 0xd000 is objects macOS builds once
the GPU has work.

**The fix is bundle 0x8ed8, the mask of MTR sensors the firmware reads.**
Our driver left it zero, so the firmware read no sensors, and when PMP's
GPU loop raised an alarm the firmware found no sensor to match it. On
the J713 it is 0x6b79: sensor IDs 0, 3, 4, 5, 6, 8, 9, 11, 13 and 14,
exactly the IDs `/arm-io/pmgr` `mtr-polynom-fuse-agx` lists. m1n1 passes
them as `apple,m4-sensor-mask` (stage 2 patch 0018), and the driver writes
the mask. Setting only this word stops the crash and starts sampling:
nine records from bundle 0x8498 (0x28 bytes per sensor ID) and a summary
at 0x8e9c fill in, at about 400 samples a second, around 30 °C at idle.

An earlier version of the fix set region C +0x30 instead. That is
automatic idle: it stopped the crash only because the idle GPU powers off
and disarms its alarms, and sampling stopped with it. Automatic idle stays
off until waking the GPU for work can be tested; with the GPU loaded it
costs about 0.15 W at idle (4.40 W against 4.26 W, one minute each).

Bisect, each run loading the GPU and then PMP with its GPU loop:

| macOS values applied | crash | sensors read |
|---|---|---|
| none | yes | no |
| all 208 configuration words | no | yes |
| header, register-window flags, slot 36, chip words, tables | no | no |
| power controllers, region C, SoC-hot route, 0xaee4 floats | no | no |
| bundle 0x8ec0-0x8ee0 (92, 108, 0x6b79, 1) | no | yes |
| only bundle 0x8ed8 = 0x6b79 | no | yes |
| only region C +0x30 = 1 (automatic idle) | no | two samples, then off |

(Without the mask, "crash: no" in the middle rows comes from region C
+0x30, which those runs still had.)

Also set to macOS's values, from the same comparison:

- Region C 0x88, 0x8c and 0x98, the performance-state limits in hundredths
  of a state: 900, the top state, where the driver had 1000.
- Bundle 0x8288, 0x8290 and 0x8294, the SoC-hot alarm route: the fast-die
  sensors, 125 and 1, as Asahi fills `fast_die0_sensor_mask64_2`,
  `unk_e24` and `unk_e28` on older GPUs.
- Bundle 0xfb8, 0xfbc and 0xfc0, the GPU's identity: class 0x1b, a
  revision code (1, 3 or 4 for A0, B0 and B1; the J713 is B1, so 4) and
  10 cores.

Field meanings come from Asahi's open initialization data and from Syd
Garlathy's interface notes (`~/Universal/M4-Nix/gpu/re-notes/`), written
from macOS's drivers and checked here against the J713.

Tested on the J713: both load orders, and a boot with both drivers
autoloading. No crash, and the firmware samples its sensors continuously.
Soaked on 2026-11-17: two hours with the mask, limits and SoC-hot route
(no crash, about 480 samples a second throughout, 3.65 to 4.0 W for the
whole system on charge), then six hours with the identity words added,
also without a crash
(`firn-gpu-runs/soak-20261117.log`).

Left for later: see "Open" under "Rendering" below.

Also worth checking: Firn keeps the GPU power domain on because "PMP reads
the GPU block while it runs". That is likely the LTS loop reading
MTR_TOP_AGX.

## Rendering (2026-11-18)

### The branch

`firn/gpu-next` brings the driver up to Gravity Linux's `bits/210-gpu`
(9 November) for the base M4, in reviewable commits:

1. Niklas's commits after our first snapshot, from his `bits/210-gpu`
   (27 October), as he wrote them and in his order. The driver tree then
   matches his tip byte for byte.
2. Cody's widening of the native mesh experiment, split out of Gravity's
   88,000-line squash (`ed2c67a9f6d4`) under his authorship. The rest of that
   squash is the M4 Pro, Max and M5 drivers, or adapters to Gravity's own Rust
   APIs, which Firn's port already covers.
3. Niklas's commits on Gravity after the squash: a lower fast-die limit knob,
   fdinfo memory accounting (with his Rust `show_fdinfo` hook ported to
   mainline's `DriverFile`), per-VM compute pools, a smaller render ring,
   deferred-close reaping and the operand-pool lower bound.
4. Firn's port commits (RTKit registration, 7.4, mainline dma_fence), redone
   on the split files, then Firn's fixes on top.

Left out: Niklas's hook that publishes GPU activity to Gravity's PMP memory
and fabric vote driver (`pmp-cpu-vote.c`). Firn has no such driver, and it
writes PMP votes, which needs its own review.

The base-M4 files then equal Gravity's tip apart from those adapters. Most
of Niklas's newer commits carry no `Signed-off-by` (see TODO).

### Mesa

Gravity's Mesa (`GravityLinux/mesa` `f66f380c648`, 11 November), built on the
Air with four to six cores from `scratchpad/gpudeploy-next/mesa.nix`, an
override of nixpkgs' Mesa 26.1.8 recipe: asahi, llvmpipe and softpipe, the
asahi and swrast Vulkan drivers, no rusticl, and Mesa 26.3's clang library
path. It is installed beside the system, not in it; tests point
`LD_LIBRARY_PATH`, `__EGL_VENDOR_LIBRARY_FILENAMES` or `VK_ICD_FILENAMES` at
it. It reports "Apple M4 (G16G B1)", OpenGL ES 3.0 and Vulkan 1.4.359
(Honeykrisp).

It is 1,117 commits and about 148,000 lines on top of upstream Mesa from
21 August, almost all Niklas's: the Apple9 compiler, Honeykrisp support and
their tests. A clean upstream series is its own project.

### Tests on the J713

Scripts in `~/Universal/M4-Nix/gpu/firn-gpu-runs/tests/`, results in
`runs-next/`.

| Test | Result |
|---|---|
| `eglclear`: clear, one triangle, read back, exact compare | 1,000 frames, every pixel right |
| `vkmark`, headless, default suite | score 3656 before the idle fix, 5498 after |
| `kmscube -A` on `card1` (DCP) | 600 frames at 59.97 FPS on the panel |
| `vkmark` at 3840x2160, 10 minutes | no fault, 13.7 W average |
| heaviest scene held at 4K | the firmware holds the hottest sensor at 109-110 C, trimming 27 W to 23 W |

The GPU powers off when idle and wakes for each submission; idle system
power stays at 3.2 W. No submission was rejected and the safety poll never
had to retire work.

### The MTR crash, again

Niklas found the same crash on the Mac mini and fixed it by mapping register
window slot 36 (the MTR block); he also found the `extra_0` policy object,
which left zero makes PMP's loop pin the GPU at its lowest state. With all
three in one tree, the debug branch's switches showed on the J713:

| `extra_0` | slot 36 | sensor mask | result |
|---|---|---|---|
| zero | no | no | MTR "no match" crash |
| zero | yes | no | MTR "no match" crash |
| zero | no | yes | no crash, sampling |
| built | no or yes | no | no crash, no sampling |

The zero `extra_0` object is what raises the alarm; the empty mask is what
makes it fatal. macOS sets all three, and so does the branch.

### Region C

Tested by loading macOS's values over ours with the debug overlay:

- **Automatic idle timing** (+0x34, +0x7c4 to +0x7e8, +0x9b8 to +0x9c0):
  all zero but one, so the GPU powered off between frames. From the
  `/arm-io/sgx` properties now, with macOS's J713 values as defaults: 49 %
  more `vkmark`.
- **Watchdog thresholds** (+0x24, +0x9c8, +0x9cc, +0x9d0) and the
  **keepalive thresholds** (+0x7f4, +0x7f8): set as macOS does, no
  measurable change.
- Still differing, with no measurable effect: +0x3c, the packed fields at
  +0x5e to +0x6a, +0x7f0 and +0x998 to +0x9a0. +0x80 and +0x988 to +0x990
  are runtime state.

The controller words macOS shows at a 16.667 ms cadence (bundle +0x5384,
+0x7f68, +0x7f6c, +0x7d58, +0x7614) are not wrong values: macOS publishes
the display's frame period (+0x988, +0x990, then control message 0x22) and
the firmware retunes. The driver does not send that message yet.

### Open

- **The chassis.** Under sustained GPU load the chassis passes the 45 C the
  chassis zone holds the CPUs to (48 C seen): the zone has only the CPUs as
  cooling devices. The GPU needs a cooling device that lowers its
  performance-state limit at runtime; how macOS does that is a question for
  Syd.
- **Display cadence** (message 0x22), as above.
- **Workarounds in the imported driver:** a 50 ms safety poll that retires
  Work whose completion notification never came (never fired on the J713
  so far); "A4 wedge" detection, which only reports a render whose fragment
  stage never starts; operand pools below 8 refused because they hang the
  GPU. None has a known cause.
- **The native mesh experiment** stays off by default and advertises itself
  through a sysfs line, not the UAPI; Mesa treats a missing line as off.
- **DCP:** `kmscube` without `-A` gets EBUSY on its first legacy page flip.
- **Region C** words above, and `0x7fffffff` in a sensor's current
  temperature now and then (between samples, by the look of it).
- **Mesa in Firn:** a package and `hardware.graphics` once the kernel series
  takes the driver.

### Memory clock

Measured with a single-core pointer chase and memcpy
(`tests/membench.c`), nothing written to PMP: idle or CPU-only, 365 ns and
9.9 GB/s; light GPU load, 135 to 148 ns and 25 to 28 GB/s; heavy GPU load,
101 ns and 44 GB/s, within 5 s of the load starting and back within 5 s of
it ending. PMP scales memory with GPU demand by itself, so the GPU does not
need Gravity's activity hook. CPU work gets no floor at all (TODO).

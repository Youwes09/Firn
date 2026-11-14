# GPU (T8132, G16)

Not supported yet. The kernel series has no GPU driver, and the policy check
makes sure none is built.

The driver is being ported on its own branch, `firn/gpu`: Cody Ho's and
Niklas Sheth's `asahi_m4` history on Firn's kernel, moved to mainline's
dma_fence and to an RTKit registration the device owns. It builds, and the
firmware boots and stays up on the J713 with PMP running (see "First runs"
below). Nothing has rendered yet: that needs Mesa with G16 support.

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
  macOS uses for this was missing. That was the real bug (fixed below).

### Fix: region C +0x30

Niklas Sheth sent macOS 26.6.2's initialization data from a J713, read
with macOS paused after boot (`~/Universal/M4-Nix/gpu/niklas-postinit-20261110/`:
root, main, the 128 KiB bundle, regions A and C). The driver's `fw_mem`
debugfs file gave the same objects from our driver after boot, with PMP
held off (`firn-postinit-20261113/`). The two were diffed word by word
(`firn-gpu-runs/initdata-diff/`).

The macOS-only values were applied in groups by a debug module parameter,
loading the GPU and then PMP with its GPU LTS loop intact:

| macOS values applied | GPU firmware |
|---|---|
| none | crashes |
| second fast-die mask, 125, 1 (bundle 0x8288, Asahi's `fast_die0_sensor_mask64_2`, `unk_e24`, `unk_e28`) | crashes |
| map slot 36 (GPU + 0xe00000) | crashes |
| HwDataB words 0xea4-0xfc0 | crashes |
| tables at 0x2544-0x32c4 | crashes |
| power floats | crashes |
| bundle header words | crashes |
| bundle 0x8ec0 block (92, 108, 0x6b79, 1) | runs |
| only bundle 0x8ed8 = 0x6b79 | runs |
| region C words | runs |
| only region C +0x30 = 1 | runs |
| all of the above | runs, and the firmware's sensor record fills in |

Region C +0x30 = 1 is the fix (`firn/gpu` 9cd14bdc1678): macOS sets it, and it is a flag rather than
a measured value. Asahi's region C layouts (13.x) have flags here that are
1 on newer GPUs (`unk_28`, `unk_2c_0`); which one it matches on G16 is not
settled, so the driver doesn't name it. 0x6b79 is not in the ADT, and it
may be state macOS or the firmware writes at run time, so it isn't used.

With the fix, the GPU firmware and PMP ran for two minutes in both load
orders (GPU first, PMP first) with no crash. Booted with both drivers
autoloading (firmware up at 3.5 s, PMP at 4.3 s), the system ran 13 hours
with no crash. The test system's recipe is in `firn-gpu-runs/deploy-fix/`.

With only the fix, the firmware's sensor record (bundle 0x8e9c) keeps its
placeholder values; with every macOS value applied it reads 31-39 °C. One
of the other groups turns sensor reading on.

Left as found: the rest of the diff. Our region C +0x24 is 4096 where
macOS has 3000 (Asahi's `unk_24_0` is also 3000); macOS also maps slot 36
and sets the HwDataB words above, which Asahi sets for older GPUs too. The
core voltages differ by about 5-15 mV, which is the two chips' own
calibration.

Also worth checking: Firn keeps the GPU power domain on because "PMP reads
the GPU block while it runs". That is likely the LTS loop reading
MTR_TOP_AGX.

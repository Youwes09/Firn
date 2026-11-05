# GPU (T8132, G16)

Not supported yet. The kernel series has no GPU driver, and the policy check
makes sure none is built.

## Measured on the J713

- `ID_VERSION` `0x0a021100`: G16, variant G, revision B1.
- `CORE_MASK` `0x3bd`: cores 1 and 6 fused off.
- ADT `/arm-io/sgx`: `gpu,t8132`, 16 performance states up to 1470 MHz.
- iBoot reserves the UAT regions at `0x103fff70000` but leaves them empty;
  the driver has to build the tables.

## What a driver needs on the J713

- **Firmware `mBoot-18000.161.10`** (macOS 26.6.x). Firn now installs a
  macOS 27.2 stub (`mBoot-20457.41.3`), so the handoff has to be ported to
  that firmware first.
- **Ten performance states.** Gravity Linux's `asahi_m4` driver, in its
  `gravity-m4` kernel, reads exactly eleven.
- **m1n1's GPU handoff**, in Gravity Linux's bootloader: the memory regions,
  firmware build, core mask and performance tables. When it fails, stage 2
  boots without the GPU instead of stopping.

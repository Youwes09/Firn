# GPU (t8132, G16)

The GPU driver is Gravity Linux's `asahi_m4` (`DRM_ASAHI_M4`) from the
`gravity-m4` kernel, with userspace from Gravity's Mesa. The shipped kernel
leaves it off until it runs on the J713; a test generation builds it as a
module that is loaded by hand.

## What the J713 needs

- **Firmware `mBoot-18000.161.10`** (macOS 26.6.x). The driver accepts no
  other build. The installer puts a macOS 26.6.2 stub beside macOS, which
  provides it.
- **Ten performance states.** The J713's GPU has ten; `gravity-m4` reads
  exactly eleven. Gravity's Linux 7.3 driver reads tables of any length.
- **m1n1's GPU handoff**, from Gravity's bootloader: the memory regions,
  firmware build, core mask (`0x3bd` on the eight-core GPU) and
  performance tables.

## Measured on the J713

- `ID_VERSION` `0x0a021100`: G16, variant G, revision B1.
- `CORE_MASK` `0x3bd`: cores 1 and 6 fused off.
- ADT `/arm-io/sgx`: `gpu,t8132`, 16 performance states up to 1470 MHz.
- iBoot reserves the UAT regions at `0x103fff70000` but leaves them empty;
  the driver builds the tables.

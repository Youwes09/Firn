# Known issues

Open problems on the J713, with what is known and what is not. Each entry
records the evidence, so a later test starts from it rather than from scratch.

## 1. The NVMe controller crashes under sustained writes

**Status:** open, reproducible. Normal use is unaffected; avoid writing more
than a few GB in one burst (build on another machine and copy the results).

**Reproduction:** about 3.8 GB written in about 20 s (`head -c 96M /dev/urandom
| split` into 20 directories of small files on the root filesystem). The ANS
co-processor takes an SError and RTKit cannot recover it:

```
nvme-apple 4c5cc0000.nvme: RTKit: co-processor has crashed
  ESR    = 0xbe000000
nvme-apple 4c5cc0000.nvme: RTKit crashed; unable to recover without a reboot
```

The root filesystem then returns I/O errors until a forced power-off. The next
boot replays the ext4 journal; a forced fsck afterwards found nothing to fix.

| | Crash 1 | Crash 2 |
|---|---|---|
| Driver | Asahi `nvme-apple`, `flush_interval=0` | upstream `nvme-apple` with the t8132 patch |
| Written before crash | ~3.8 GB, 20 of 100 directories | ~3.8 GB, 20 of 100 directories |
| Firmware PC | `0xae00c` | `0x3ca004`, firmware loaded `0x31c000` higher: `0xae004` |
| FAR | `0x100000045ac` | `0x100000045ac` |
| ANS internal APCIE links | link 0 in L0, link 1 in L1_IDLE | the same |
| Unmasked HWINTMON 0, 1, 2 | `0x1`, `0x40`, `0x8000` | the same |
| Thermal throttle level | 1 | 1 |
| NAND errors (UECC, PFAIL, EFAIL) | 0 | 0 |

FAR is not architecturally valid for an SError, so its match may be a stale
value; the PC match after correcting for the load address is the stronger
evidence. Both crashes stop in the same firmware function.

**Ruled out:**

- The Linux driver: both drivers crash identically.
- The NAND: the firmware's own report shows no media errors, and SMART after
  crash 2 shows 0 media errors, 100% spare, 1% used.
- Linux powering down a domain: `ans`, `apcie_st`, `apcie_sys_st` and
  `apcie_phy_sw` are all on (`pm_genpd_summary`).
- The delayed flush (#167): `nvme_apple.flush_interval=0` does not help.

**Lead:** on t8132 the external PCIe controller (`pcie@1cb0000000`, the Wi-Fi)
and its DART are in `apcie_phy_sw`, a child of `apcie_sys_st` and `ans`: they
share the ANS power tree, unlike t8103 and t8112. Both crashes ran with network
traffic over Wi-Fi.

**Next tests (each may cost one crash):**

1. The same write test with `brcmfmac` unloaded and SSH over USB Ethernet. A
   pass points at the shared APCIE tree.
2. A rate-limited write test (cgroup `io.max`) to find the throughput at which
   it starts. This also gives a workaround if the cause stays unknown.

Record `nvme smart-log /dev/nvme0` before and after each test, and stream the
journal to another machine (`journalctl -f` over SSH) to keep the crash report.
Crash logs from both runs are kept outside the repository.

## 2. The trackpad does not always start

**Status:** fixed in the series (patches 0018–0021). On 2026-10-27 the
trackpad reported `Touch MT ready` on 4 of 4 reboots and on a cold boot
with the AFE reset, against 0 of 4 start attempts without it. A 40 s
`evtest` capture showed movement across the pad, 82 click press/release
pairs, up to four contacts and no dropped events.

The multi-touch firmware rejects the stock version 1 interface reset. On
the source kernel without the fix:

```
dockchannel-hid 394b30000.input: Resetting multi-touch
dockchannel-hid 394b30000.input: output report 0x40 to iface 0 (comm) failed with err 0xe00002c2
```

and opening the device fails with `EIO`. The installer kernel sends the
version 2 request (`dockchannel_hid.m4_power_v2=1`). With it the trackpad
started on 2026-10-26 (`Touch MT ready`, touch events seen with `evtest`)
but timed out on earlier boots:

```
dockchannel-hid 394b30000.input: Resetting multi-touch
dockchannel-hid 394b30000.input: iface multi-touch start timed out
```

after which every open failed with `EINPROGRESS` because the driver never
cleared its starting flag.

The timeouts came with the firmware's own report that the AFE did not
boot:

```
afe_bl_trp_hbpp.c:175: AFE Chip Boot Failure for HBPP[0]: No HINT_L
afe_pwr.c:676: AFE[0] bootload failed: 1
```

The version 2 request has two phases per state change, and the host is
meant to reset the AFE between them. The installer kernel sent both phases
back to back, so the AFE started only when it happened to come up anyway.
On the J713 the AFE reset is an SMC action on `gP1c` (GPIO 28, the
`apple,afe-reset-gpios` pin): argument 1 holds the AFE in reset, 50 ms,
then argument 0 releases it (Omarchy-M4-Native's
`docs/j713-afe-native-action.md`). Setting the pin's output is not the
same and does not work.

The series:

- selects the version 2 request through the
  `apple,t8132-dockchannel-hid` compatible (0018);
- clears the starting flag on a start timeout, so the next open tries
  again (0019);
- exports `macsmc_gpio_action()` from the SMC GPIO driver (0020);
- runs the AFE reset between the two phases (0021).

## 3. Kernel parameters that did nothing

`pcie_apple.m4_link_diag=1`, `pcie_apple.m4_keep_clocks=1` and
`dockchannel_hid.m4_afe_action=1` are in the installer's qualified set, but
no kernel tree defines them. `m4trace_hit=999` only arms a watchdog reset at
a trace point that never fires. The source kernel and this repository drop
all of them; only the installer's own boot.bin still carries them.

## 4. The clock is months behind in early boot

The first fsck of the root filesystem saw the time as March 2026 and the
superblock's last write as in the future, until NTP set the clock. Nothing
reads the RTC early. Harmless so far; it will matter for anything that checks
certificates or timestamps before the network is up.

## 5. Workarounds whose cause is unknown

- `irqchip/apple-aic`: on t8132 the EL2 guest timer FIQ enables and
  `ICH_HCR_EL2` are not written (patch 0006). m1n1 reports the Apple system
  registers as locked on M4 (`apple_sysregs_unlocked` is false), which may be
  the cause. Until it is solved, KVM guests get no timer interrupts.
  Yureka Lilian's M4 tree carries the same workaround (`7c74add40c06`).
- `arm64.nowfxt`: WFIT in `__delay()` reportedly stops the M4 at EL2. Not
  yet confirmed by booting without it.

## 6. The loader from source has not booted

`hardware.m4-j713.loader` defaults to the installer's m1n1. The `"source"`
setting builds m1n1 from `c9ef56f7` with the stage 2 patch and the trust
cache reservation, but has not booted yet. It cannot be compared with the
installer's loader by hash: that one was built with a distribution
toolchain (Rust 1.93), so the binaries differ even for the same source.

The devicetree from the kernel series (`hardware.m4-j713.devicetree =
"source"`, used by the example configuration) booted on 2026-10-27, five
times: SMC, NVMe, Wi-Fi, Bluetooth, keyboard and trackpad came up, with
the mailbox interrupts in binding order and no `nvmmu` window.
`checks.devicetree` lists every difference from the release binary. The
release devicetree still works with this kernel, but without the
trackpad: it lacks the compatible that selects the version 2 reset.

## 7. Not yet at Asahi standard

- KB2UKA's patches carry only the committer's sign-off, under clause (b)
  of the Developer's Certificate of Origin; checkpatch reports
  NO_AUTHOR_SIGN_OFF until their author adds one.
- `make dtbs_check` (`checks.devicetree-schema`) still reports the
  downstream drivers that have no binding on any Apple SoC: AOP, MTP,
  dockchannel, SEP, ATC PHY, display crossbar and the GPU.
- The CPU frequency tables stop at the clocks iBoot hands over. That keeps
  the Air cool without a thermal policy, but it is policy in the
  devicetree, which upstream does not take.
- The unported GPU driver (about 8,500 lines in `drivers/gpu/drm/asahi`, plus
  RTKit and Rust binding changes it needs) is not in the series.
- The kernel links with GNU ld; their build used LLD.
- The kernel keeps the installer kernel's version string,
  `7.1.9-m4-gpu-backport-20261008`.

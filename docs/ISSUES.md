# Known issues

Open problems on the J713, with what is known and what is not. Each entry
records the evidence, so a later test starts from it rather than from scratch.

## 1. The NVMe controller crashes under sustained writes

**Status:** open, cause not found. Normal use is unaffected; avoid writing
more than a few GB in one burst (build on another machine and copy the
results).

**Reproduction:** `head -c 96M /dev/urandom | split` into small files plus
40 MB of larger files per directory, on the root filesystem, without pauses.
Every unpaced run crashes while writing directory 39 of 100, about 22 s in,
with about 3 GB on disk. The ANS co-processor takes an SError and RTKit
cannot recover it:

```
nvme-apple 4c5cc0000.nvme: RTKit: co-processor has crashed
  ESR    = 0xbe000000
  FAR    = 0x100000045ac
nvme-apple 4c5cc0000.nvme: RTKit crashed; unable to recover without a reboot
```

The root filesystem then returns I/O errors until a forced power-off. The
next boot replays the ext4 journal. After five crashes SMART shows 0 media
errors, 100% spare and 1% used.

| | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Kernel | installer | installer | series | series | series + debug |
| Change under test | | upstream driver | Wi-Fi and Bluetooth unloaded | 60 s pause per GB | `ps_ans` `apple,min-state = <15>` |
| Crashed at | dir 39 | dir 39 | dir 39 | 12.4 GB, 5 s after a pause | dir 39 |
| FAR | `0x100000045ac` | the same | the same | the same | the same |
| Internal links | L0, L1_IDLE | L0, L1_IDLE | L1_IDLE, L0 | L1_IDLE, L1_IDLE | L0, RCVRY_LOCK |
| NAND errors | 0 | 0 | 0 | 0 | 0 |

**What the evidence shows:**

- The firmware faults while it wakes one of its two internal APCIE links to
  the NAND (`106b:2006`) from L1. Crash 5's LTSSM trace for link 1 runs from
  L1_IDLE through the exit sequence into Recovery.Lock, where it stopped;
  crashes 3 and 4 caught the links in L1_IDLE. The links enter L1.2 over a
  thousand times per run.
- The I/O queues were empty or idle at the crashes: the firmware was doing
  its own work, not serving a command.
- The FAR is the same at every crash although the firmware loads at a
  different address each boot. It is below the RAM Linux is given (System
  RAM starts at `0x10001df4000`).
- Bursts reach it at about 3 GB; one paced run (sync and 60 s pause per GB)
  reached 12.4 GB and crashed 5 s after writing resumed. Omarchy-M4-Native
  #167 reports six clean 33.7 GB `cp -a` copies on a J715 (reads and writes
  together) with `flush_interval=0`.
- The crash log's `Ccst` section is the faulting call stack: PC `0x146004`,
  then `0x138c58`, `0x1bd9f8`, `0x18c6b0` (crash 5).

**Ruled out:**

- The kernel and the driver: installer and series kernels, Asahi and
  upstream drivers crash the same way.
- The NAND: no media errors in any crash report or in SMART.
- The delayed flush (#167): every series crash ran with
  `flush_interval=0`, confirmed in `/sys/module/nvme_apple/parameters`.
- The Wi-Fi sharing the ANS power tree: crash 3 ran with `brcmfmac` and
  `hci_bcm4377` unloaded.
- NVMe power states and host memory buffer: the controller reports none
  (`npss 0`, `apsta 0`, `hmpre 0`). `/` is mounted without `discard`.
- The macOS 15 firmware changes Sven Peter fixed (no TCB opcode, no DMA
  direction without data, no PRP chicken bit): the driver has them.
- SART version: `apple,t6000-sart` selects the v3 ops, as on t8112.
- Auto power gating of the ANS domain: Linux enables it where iBoot leaves
  it off (`ps_ans` `0x1f0020ff` against `0x0f0020ff`), but crash 5 ran with
  `apple,min-state = <15>` (`0x1f0f20ff`) and crashed the same way.
- Restarting ANS without the PMGR reset, to keep iBoot's setup: the
  firmware does not boot from m1n1's sleep that way (`ANS did not boot`).

**Limits of observation:** the ANS link block (`0x483000000`, 16 MB) and
the NVMMU window are firewalled from the application processor. In m1n1's
proxy every read hangs the bus; from Linux a single read raises an
asynchronous SError and panics the kernel. During normal operation the
firmware sends no RTKit or IOReport messages and logs nothing; it reports
only at boot and in the crash log.

**Open leads:**

1. `tunable-table-bundle = "akpvuzkn"`: the ADT's `ans` node lists
   `storage-lane-common-tunables` and three other tunables as empty and
   names this bundle instead, the only one in the ADT. The bundle is not in
   plain text anywhere in macOS, so iBoot probably applies it. Nothing in
   m1n1 or Linux applies it after the PMGR reset.
2. NVMe vendor log pages, which may carry link or error statistics.
3. m1n1's hypervisor running macOS, to see what macOS writes. On M4 the
   Apple system registers are locked and GXF initialisation is known to
   fail, so this likely needs m1n1 work first.

Crash logs, traces and per-second samples are kept outside the repository.

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
all of them.

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

## 6. The boot chain from source: what has booted

Booted on a J713 (2026-10-27, six boots): the devicetree from the kernel
series (SMC, NVMe, Wi-Fi, Bluetooth, keyboard and trackpad came up), and
m1n1 stage 2 from `c9ef56f7` with the trust cache reservation and
Omarchy-M4-Native's GPU handoff patch, behind their installer and stage 1.

Not yet booted on hardware:

- the installer built from asahi-installer with `pkgs/installer/patches`,
  which writes `<ESP>/m1n1/boot.bin` and passes the EFI partition as
  `asahi,efi-system-partition`;
- m1n1 stage 1 built from `c9ef56f7` with the issue #82 patch;
- m1n1 stage 2 without the GPU handoff patch: upstream m1n1 reports the
  T8132 GPU as unsupported and leaves its devicetree node alone, and the
  GPU's memory regions stay disabled.

Open: which `/memreserve/` entry is the trust cache. The patch stops the
boot if the reservation fails, and it did not, but confirming the address
needs the ADT, which m1n1 passes as a `phram` region. The kernel has no
MTD support and `STRICT_DEVMEM` blocks `/dev/mem`, so neither the ADT nor
m1n1's log can be read on the Air as configured.

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
- The GPU: Asahi's driver is in the tree but has no G16 support yet, and
  the kernel does not build it; see [GPU.md](GPU.md).
- The kernel links with GNU ld; their build used LLD.

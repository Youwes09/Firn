# Known issues

Open problems on the J713, with what is known and what is not. Each entry
records the evidence, so a later test starts from it rather than from scratch.

## 1. The NVMe controller crashes under sustained writes

**Status:** open, cause not found. Normal use is unaffected; avoid writing
more than a few GB in one burst (build on another machine and copy the
results). Crashes 1 to 5 ran on the earlier Gravity-based kernels; the
mainline series has not been tested yet.

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

## 2. The clock is months behind in early boot

The first fsck of the root filesystem saw the time as March 2026 and the
superblock's last write as in the future, until NTP set the clock. Nothing
reads the RTC early. Harmless so far; it will matter for anything that checks
certificates or timestamps before the network is up.

## 3. Workarounds in effect

Each stands in for a fix that is not done yet ([TODO.md](TODO.md)).

- **No sleep.** Suspend and hibernate are refused, and closing the lid
  powers the Air off.
- **Capped CPU clocks.** Nothing throttles the CPUs yet, so `firn-cpu-cap`
  holds the P cores at 1.8 GHz and the E cores at 2.17 GHz, about 74 C under
  load.
- **`idle=nop`.** A plain wfi loses the core's registers on T8132, so the
  default idle path must not run; cpuidle idles the cores.
- **`arm64.nowfxt`.** WFIT in `__delay()` stops the M4 at EL2.
- **No KVM guest timers.** AIC skips the EL2 guest timer FIQ enables and
  `ICH_HCR_EL2` on T8132, as writing them hangs the boot. m1n1 reports the
  Apple system registers as locked on M4, which may be the cause.
- **`nvme_apple.flush_interval=0`**, after Omarchy-M4-Native #167; the
  crash in issue 1 happens with or without it.

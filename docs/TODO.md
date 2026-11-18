# To do

Open work, most pressing first. Known problems with the current system are
in [ISSUES.md](ISSUES.md).

## Check on the Air

- [ ] USB-C: both left ports in both orientations, USB 2 and USB 3 devices,
      charging, hotplug, a USB Ethernet adapter.
- [ ] Lid power-off and Bluetooth pairing.
- [ ] Idle power and temperatures against the Gravity-based kernel.
- [ ] PMP: the report post-ready sequence completes, and unbinding the
      driver is clean.
- [ ] Whether a non-zero byte 7 in a DockChannel ACK header is an error.
      Gravity Linux treats `hdr->pad >> 8` as -EIO; the driver calls bytes
      6 and 7 opaque.
- [ ] The NVMe write crash (ISSUES.md 1) on the mainline series.
- [ ] firn-link: the build machine's access point drops the Air after
      about ten idle minutes, and iwd on the Air does not notice.

## Workarounds to replace

- [ ] Sleep, which needs every co-processor's power states understood.
- [ ] AIC's skipped EL2 FIQ masks: find why the writes hang.
- [ ] brcmfmac on a busy public network: `GET STA INFO failed, -52` and
      `escan_handler: Buffer is too small: ignoring`, not seen at home.
- [ ] The page flip timestamp HACK in the DCP driver, which moves
      completion up to 1 ms earlier. There is nothing to replace it with
      yet: on 26.6 the swap complete callback carries no timestamp (only
      two frame counters, at 0x3f0 and 0x700, change between frames), and
      none of the nine ADT `disp0` interrupts reaches the AP during 60 Hz
      flips. The callback arrives 16.05 to 16.11 ms after each swap.
- [ ] `nvme_apple.flush_interval=0`, kept from an Omarchy-M4-Native report.

## Kernel

- [ ] Audio: MCA, ADMAC, SIO, then the codecs with speaker protection.
- [ ] GPU, as its own series ([GPU.md](GPU.md)):
  - [x] First boot with m1n1's J713 calibration and `asahi_m4`, at the Air.
  - [x] Fix the MTR alarm crash with PMP running (GPU.md, "Fix").
  - [x] Automatic idle with wake on work, and its timing (GPU.md,
        "Region C").
  - [x] The watchdog thresholds, the register-window access flags and
        slot 36.
  - [x] Render with Gravity Linux's Mesa (GPU.md, "Rendering").
  - [ ] A GPU cooling device for the chassis zone.
  - [ ] The display cadence message (0x22).
  - [ ] Find the causes behind the safety poll, the A4 wedge and the
        operand-pool lower bound.
  - [ ] Bring `firn/gpu-next` into the kernel series; let
        `tests/policy.nix` allow `DRM_ASAHI_M4`; package Mesa and enable
        `hardware.graphics`.
  - [ ] Mesa as a clean series of its own (1,117 commits on upstream).
  - [ ] Gravity's PMP memory and fabric vote driver and the GPU's hook
        into it, after review (it writes PMP votes).
  - [ ] Document `apple,agx-t8132` in `apple,agx.yaml`; the node is not
        validated today.
- [ ] DisplayPort alt mode and external displays.
- [ ] RTKit oslog types 3, 4 and 5: 4 and 5 are the firmware's image ID and
      name; decode 3 before handling them.
- [ ] `capacity-dmips-mhz` and `clock-latency-ns` for the CPUs, measured on
      the J713.
- [ ] The PMU's `fault_shadow` and `socd` cells (ADT `info-fault_shadow`,
      `info-scrpad_socd`), as t8112 describes them.
- [ ] hwmon-common's `PMVR` key does not exist on the J713 SMC.
- [ ] The arm64 crypto extensions (AES, GHASH, SHA) for Wi-Fi and
      WireGuard.
- [ ] `ARM64_BTI_KERNEL`, once mainline allows it with Clang 21.
- [ ] DCP's 26.6 callbacks D202 (unmap PIODMA) and D454 (release memory),
      once the J713's firmware is seen to send them.
- [ ] Sasha Finkelstein's PMP driver numbers T6000 SetIOReg entries from 1
      but looks them up from 0; check against a T6000 trace.
- [ ] The M4 wfi erratum's KVM part (always trap a guest's wfi) is only
      compile-tested; Firn's kernel has no KVM.
- [ ] CPU0 keeps its registers through wfi, so its power-down state may
      never power it down; measure its idle power alone.

## Upstreaming

- [ ] Bindings for the MTP, DockChannel, DockChannel HID, DCP and the J713
      panel; `checks.devicetree-schema` lists them as expected warnings.
- [ ] Sign-offs from their authors, for commits that carry only Firn's:
      Yureka Lilian's SMC and PCIe devicetree; Niklas Sheth's PMP, RTKit
      endpoint 7, tipd, DPTX endpoint and two brcmfmac fixes; Cody Ho's
      PMP devicetree and his two display fixes from Gravity 83fb190f1108;
      KB2UKA's reboot and AIC commits; Janne Grunau's "Warn only once
      about failed calls" and 12.3 flush fix, unsigned in Asahi's tree.
      On `firn/gpu`: Cody Ho's RTKit early crashlog (1d87a283bc6b) and
      Niklas Sheth's GPU devicetree (a4092eb5b591). On `firn/gpu-next`:
      47 of Niklas Sheth's 50 newer G16 commits, and his `show_fdinfo`
      Rust hook.
- [ ] checkpatch clean-ups in cpuidle-apple, Sasha's M3 ATC PHY and Alba
      Mendez's SPMI commits; a fuller Kconfig help and MAINTAINERS entries
      for the PMP drivers, whose bindings name Sven Peter as maintainer.
- [ ] Report to Asahi Linux: the dropped brcmfmac roam delta, the
      `RUST_APPLE_RTKIT` select, and the DCP driver's uninitialised `ret`
      in the mNits parser, uncleared mode slots and missing blend mode
      property.
- [ ] Report to Gravity Linux: the Mac mini's Wi-Fi board type
      (`apple,asakhali`, the ADT says `sakhalin`), the DART binding's
      dropped five-cell `#iommu-cells`, and dwc3_2's IRQ (387, the J773
      ADT says 1403).
- [ ] `t8132-jxxx.dtsi` gives J604, J623, J624 and J715 a Bluetooth node
      without `brcm,board-type`; only J604 (`guam`) has ADT data.

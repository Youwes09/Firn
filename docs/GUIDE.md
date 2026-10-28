# Installing Firn on your MacBook Air

For the 13-inch M4 MacBook Air (Mac16,12) only. This guide takes you from a
normal Mac to Firn (NixOS) beside macOS, and back again if you want.

**Keep this guide on another device (phone or PC) while you install.** For
part of the install the Mac is in recovery mode and cannot show it.

## What this does to your Mac

| Change | Undoable? |
|---|---|
| macOS is shrunk by the size you choose. Your files and apps stay. | Yes: R2 gives the space back. |
| Three partitions are added: a small macOS "stub" (about 2.5 GB, needed by Apple's boot process), a 500 MB EFI partition, and the Firn partition. | Yes: R2 deletes them. |
| Firn gets "reduced security" boot permission. **macOS keeps full security**; the setting is per OS. | Yes: removed with the stub in R2. |
| macOS itself, its recovery, and Apple's firmware partitions. | **Not touched.** |

What can still go wrong, and why the backup matters:

- Shrinking macOS is an Apple-supported operation, but a power loss or bug in
  the middle of it could damage the macOS container. **Have a backup.**
- Firn may not boot the first time. That never stops macOS from booting;
  R1 fixes Firn's boot file from macOS.
- Worst case, if the Mac will not start at all: an Apple Store, or a second Mac
  with Apple Configurator, can restore it ("DFU restore"). That erases the Mac,
  which is the other reason for the backup.

Hardware risk is kept low: speakers, GPU, CPU boost and other unfinished parts
are switched off and cannot be switched on by mistake. The CPU cannot run
faster than the speed Apple's firmware starts it at.

## Part 1: prepare (about an hour, mostly the backup)

1. **Back up.** Plug in an external drive and run a full Time Machine backup
   (System Settings > General > Time Machine). When it finishes, open Time
   Machine and restore one test file somewhere, to prove the backup works.
2. **Check macOS.** Apple menu > About This Mac: it must be **26.5.1 or newer**.
   Do not start a macOS update during this process.
3. **Check your account.** You need your macOS password, and your user must be
   an administrator (System Settings > Users & Groups shows "Admin"). If you set
   the Mac up yourself, you are its owner, which the installer also needs.
4. **Free space.** You choose how much Firn gets; 60 GB is plenty for now.
   The installer also keeps 38 GB free in macOS, so for 60 GB of Firn you
   need about 100 GB free (System Settings > General > Storage).
5. **Power and internet.** Plug in the charger and keep it in. Use a reliable
   Wi-Fi: the installer downloads a few GB of Apple's recovery files.
6. **Leave FileVault as it is.** Turning it off or on just for this takes hours
   and is a change of its own. The preflight script reports its state.
7. **Practise startup options once**, so you know them before you need them:
   Apple menu > Shut Down. Wait 10 seconds. Press and **hold** the power button
   (Touch ID key) until "Loading startup options" appears, then let go. You
   see a disk icon for macOS. Click it, then Continue, to boot macOS normally.
8. **Know the force-off:** hold the power button for 10 seconds.

## Part 2: get the kit onto the Mac

On the PC, in the Firn repository:

```sh
nix build path:.#packages.x86_64-linux.kit -o firn-kit
cp -rL firn-kit /run/media/$USER/USBNAME/firn-kit
(cd /run/media/$USER/USBNAME/firn-kit && sha256sum -c SHA256SUMS)
```

Use a USB drive formatted exFAT. The `-L` matters: the kit folder is a link into
the Nix store, and `-L` copies the real files.

On the Mac: plug in the drive, drag the `firn-kit` folder into Downloads,
eject the drive. Open Terminal (Applications > Utilities > Terminal).

## Part 3: preflight (changes nothing)

```sh
cd ~/Downloads/firn-kit
bash preflight.command        # for 60 GB of Firn; or e.g. bash preflight.command 80
```

It reads your model, macOS version, free space, charger, backup, FileVault and
existing partitions, and checks the kit's files. It writes nothing.

It also prints the number to type when the installer asks for macOS's new
size, for example `enter 185GB`. **Write it down**; you need it in Part 4.

- `RESULT: ready to install`: go on.
- `WARN` lines: read each one. A macOS newer than 26.6.2 gives one; that
  is not a stop.
- Any `FAIL`: stop and fix that first.

Then confirm the kit once more:

```sh
bash Install.command --verify-only
```

Every line must end in `OK`.

## Part 4: install (about 30 to 60 minutes)

From here on, **do not close Terminal, unplug the charger, or force a restart
while the installer is writing.**

```sh
bash Install.command
```

1. Enter your macOS password (nothing shows while you type). The installer
   starts. Press Enter after its introduction.
2. **Make space.** If there is no free space yet, choose `r` (resize). It
   asks for **macOS's new size**, not Firn's: type the number the preflight
   printed, such as `185GB`. Do not accept the default, `50%`, which halves
   the disk. The installer also shows a "Minimum new size"; if your number is
   below it, use a smaller Firn (run the preflight again with fewer GB).
   Keep macOS and both recovery environments. **Never choose an option that
   deletes or erases a partition.**

   If it reports "a large amount of overhead space" and refuses, a Time
   Machine local snapshot is in the way. Quit the installer, set Time
   Machine to back up manually, delete the snapshots, and start again:

   ```sh
   tmutil listlocalsnapshots /System/Volumes/Data
   sudo tmutil deletelocalsnapshots 2026-10-25-213000   # the date in each name
   ```
3. **Install into free space.** Choose the Firn entry when the OS list
   appears. When asked for the size, `max` uses the free space you just made.
   Keep the name `Firn`. Read the summary of what it will do, and only then
   confirm.
4. It downloads Apple's recovery files, makes the partitions, collects your
   Mac's firmware and writes the boot files. This is the long part.
5. When it finishes it explains the next step on screen and shuts the Mac down.
   **Read its instructions to the end before pressing Enter.**

### Authorising Firn to boot (in recovery mode)

Apple requires you to approve the new OS once, from recovery:

1. After the Mac has shut down, wait 25 seconds. Press and hold the power
   button once, without tapping it first, until "Loading startup options"
   appears.
2. Choose **Firn** and click Continue. The Mac starts into a recovery screen
   and opens a Terminal-like window for the installer's second step.
3. Follow the prompts there: press Enter, pick your macOS user, enter its
   password, and confirm the change of security policy for Firn. This changes
   only Firn's security setting; macOS stays on full security.
4. The Mac restarts into Firn.

If you get stuck at any point in this section, hold the power button for 10
seconds, then boot macOS from startup options. Nothing on macOS has changed;
you can run the installer again or remove the partial install with R2.

## Part 5: first boot and checks

Expect scrolling boot text, then `m4-air login:` within a few minutes. The
first boot also grows Firn's filesystem to its partition.

If it stops for more than 10 minutes: take a photo of the screen, force off,
boot macOS, and use R1.

### Stage A: log in (read-only checks)

User `m4`, password `change-me`. Then immediately:

```sh
passwd
firn-report > ~/report-1.txt
less ~/report-1.txt
```

Check in the report:

- `failed units` is empty;
- `uname` shows `7.1.9-firn`;
- CPU frequency tops out at 1800 MHz (P cores) and 900 MHz (E cores);
- every speaker and headphone driver is `not loaded`;
- temperatures at idle are well below 80 C;
- the `boot.bin` section lists the loader, kernel, devicetree and firmware.

Keyboard: Option is Alt. To switch consoles, hold Control + Option and press
F2 (add Fn if F2 changes brightness).

### Stage B: Wi-Fi

```sh
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect "Your network"
ping -c3 nixos.org
```

If there is no `wlan0`, keep `report-1.txt`; its firmware section shows why.

### Stage C: heat test (watch it)

On console 2 (Control + Option + F2), log in and run `firn-report temps`.
On console 1, run:

```sh
nix shell nixpkgs#stress-ng -c stress-ng --cpu 10 --timeout 600
```

Watch the CPU temperatures for the 10 minutes. **If any CPU reading passes
95 C, press Control + C at once** and note it. With the clock caps it should
stay well below that.

### Stage D: power

- `systemctl poweroff`: the Mac turns off and stays off. Start it again.
- Log in, close the lid: the Mac powers off.
- `systemctl suspend` is refused (sleep is not supported yet).

### Stage E: update Firn once

```sh
git clone https://YOUR-COPY-OF/firn ~/firn    # or copy it over USB
cd ~/firn
# make a harmless change, e.g. add a package in examples/minimal/configuration.nix
sudo nixos-rebuild boot --flake .#minimal
ls -l /boot/efi/m1n1/
sudo reboot
```

You should now see `boot.bin.original` (what the installer wrote) and
`boot.bin.previous`, and the Mac boots the new version.

### Stage F: recovery drill (read-only)

Boot macOS and do R1's steps 1 to 3 without copying anything, so you know the
way before you ever need it.

## Choosing macOS or Firn

- Each start: hold the power button for startup options and pick one.
- Default: in macOS, System Settings > General > Startup Disk.

## R1: Firn does not boot (fix from macOS)

1. Boot macOS from startup options. Open Terminal.
2. `diskutil list`. Find Firn's **EFI** partition: about 500 MB, type
   `EFI`, right next to the large Linux partition. Not the EFI partition at
   the very start of `disk0`.
3. `sudo diskutil mount diskXsY` (your identifier from step 2), then
   `ls /Volumes/*/m1n1/` should show `boot.bin` (and `boot.bin.original`,
   `boot.bin.previous` after any update).
4. Go back one version:
   `sudo cp /Volumes/NAME/m1n1/boot.bin.previous /Volumes/NAME/m1n1/boot.bin`.
   Or to exactly what the installer wrote: use `boot.bin.original`.
5. `sudo diskutil unmount diskXsY`, then restart into Firn.

## R2: remove Firn completely (from macOS)

Run `diskutil list` first and read it carefully. **Your macOS container is the
large APFS one; never touch it except in step 4.** If anything looks unclear,
stop and ask before running a command.

1. `sudo diskutil apfs deleteContainer diskXsA`: the small (about 2.5 GB) APFS
   container named Firn, the stub.
2. `sudo diskutil eraseVolume free free diskXsB`: Firn's EFI partition.
3. `sudo diskutil eraseVolume free free diskXsC`: Firn's Linux partition.
4. `sudo diskutil apfs resizeContainer diskXsM 0`: give the free space back to
   macOS (diskXsM is your macOS container's identifier).

Startup options then show only macOS again.

# Adds only a service, so the VM boots the shipped initrd and parameters.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.firn;
  modDirVersion = config.boot.kernelPackages.kernel.modDirVersion;
  firn-boot = pkgs.callPackage ../../pkgs/firn-boot { };
in
{
  systemd.services.firn-selftest = {
    description = "Firn VM self-test";
    wantedBy = [ "multi-user.target" ];
    after = [
      "multi-user.target"
      "firn-esp-tidy.service"
    ];
    path = with pkgs; [
      coreutils
      gnugrep
      gnused
      gawk
      util-linux
      e2fsprogs
      config.nix.package
      config.systemd.package
      firn-boot
    ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/ttyAMA0";
    };
    script = ''
      fail=0
      check() {
        if eval "$2" >/tmp/selftest.out 2>&1; then
          echo "FIRN-SELFTEST ok: $1"
        else
          echo "FIRN-SELFTEST FAIL: $1"
          sed 's/^/FIRN-SELFTEST     /' /tmp/selftest.out
          fail=1
        fi
      }
      efi=${lib.escapeShellArg cfg.efiMountPoint}

      check "booted this repository's kernel" '[ "$(uname -r)" = ${modDirVersion} ]'
      check "first boot registered the store" '[ ! -e /nix-path-registration ] && nix-store --verify-path "$(readlink -f /run/current-system)"'
      check "system profile points at this generation" '[ "$(readlink -f /nix/var/nix/profiles/system)" = "$(readlink -f /run/current-system)" ]'
      check "root filesystem grew to its device" '
        dev=$(findmnt -no SOURCE /); size=$(blockdev --getsize64 "$dev")
        fs=$(dumpe2fs -h "$dev" 2>/dev/null | awk -F: "/^Block count/{c=\$2} /^Block size/{s=\$2} END{print c*s}")
        [ "$fs" -gt $(( size * 99 / 100 )) ]'
      check "installer firmware reached /lib/firmware" '[ "$(cat /lib/firmware/brcm/firn-test.bin)" = firn-test-firmware ] && [ -f /run/vendorfw/.vendorfw.manifest ]'
      check "EFI partition named by m1n1 is mounted" 'findmnt -n "$efi" && [ -f "$efi/m1n1/boot.bin" ] || { journalctl -b -u firn-esp --no-pager; false; }'
      check "installer files moved off the EFI partition" '
        [ ! -e "$efi/gravity" ] && [ ! -e "$efi/vendorfw" ]
        [ "$(cat /var/lib/firn/installer/gravity/installer.log)" = firn-test-installer-data ]
        [ -s /var/lib/firn/installer/vendorfw/manifest.txt ]'
      check "firn-boot reads the installer boot.bin as this generation" 'firn-boot install /run/current-system --efi "$efi" | tee /dev/stderr | grep -q "already this generation"'
      check "firn-boot refuses to write on a board that is not J713" '
        before=$(sha256sum "$efi/m1n1/boot.bin")
        ! firn-boot install /run/current-system --efi "$efi" --apply 2>/tmp/err
        grep -q "apple,j713" /tmp/err
        [ "$(sha256sum "$efi/m1n1/boot.bin")" = "$before" ] && [ ! -e "$efi/m1n1/boot.bin.original" ]'
      check "suspend is refused" '! systemctl suspend'
      check "lid close powers off" 'grep -rqs "HandleLidSwitch=poweroff" /etc/systemd/logind.conf /etc/systemd/logind.conf.d'
      check "no speaker codec driver is available" '
        for m in snd_soc_tas2764 snd_soc_tas2770 snd_soc_apple_mca snd_soc_cs42l84; do
          ! modinfo "$m" >/dev/null 2>&1 || exit 1
        done'
      check "the hardware switches are on the kernel command line" '
        for p in maxcpus=10 idle=nop arm64.nowfxt; do
          grep -qw "$p" /proc/cmdline || exit 1
        done'

      if [ "$fail" = 0 ]; then echo "FIRN-SELFTEST DONE result=PASS"; else echo "FIRN-SELFTEST DONE result=FAIL"; fi
      systemctl --no-block poweroff
    '';
  };
}

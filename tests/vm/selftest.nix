# Test-only additions for the T2 VM boot. They add a service and nothing to the
# initrd, kernel or boot path, so the VM boots the shipped configuration's
# initrd and kernel parameters.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.m4-j713;
  modDirVersion = config.boot.kernelPackages.kernel.modDirVersion;
  m4-nix-boot = pkgs.callPackage ../../pkgs/m4-nix-boot { };
in
{
  systemd.services.m4-nix-selftest = {
    description = "M4-Nix VM self-test";
    wantedBy = [ "multi-user.target" ];
    after = [
      "multi-user.target"
      "m4-esp.service"
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
      m4-nix-boot
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
          echo "M4-NIX-SELFTEST ok: $1"
        else
          echo "M4-NIX-SELFTEST FAIL: $1"
          sed 's/^/    /' /tmp/selftest.out
          fail=1
        fi
      }
      efi=${lib.escapeShellArg cfg.efiMountPoint}

      check "booted the pinned kernel" '[ "$(uname -r)" = ${modDirVersion} ]'
      check "first boot registered the store" '[ ! -e /nix-path-registration ] && nix-store --verify-path "$(readlink -f /run/current-system)"'
      check "system profile points at this generation" '[ "$(readlink -f /nix/var/nix/profiles/system)" = "$(readlink -f /run/current-system)" ]'
      check "root filesystem grew to its device" '
        dev=$(findmnt -no SOURCE /); size=$(blockdev --getsize64 "$dev")
        fs=$(dumpe2fs -h "$dev" 2>/dev/null | awk -F: "/^Block count/{c=\$2} /^Block size/{s=\$2} END{print c*s}")
        [ "$fs" -gt $(( size * 99 / 100 )) ]'
      check "installer firmware reached /lib/firmware" '[ "$(cat /lib/firmware/brcm/m4-nix-test.bin)" = m4-nix-test-firmware ] && [ -f /run/vendorfw/.vendorfw.manifest ]'
      check "EFI partition named by m1n1 is mounted" 'findmnt -n "$efi" && [ -f "$efi/omarchy/boot.bin" ]'
      check "m4-nix-boot reads the installer boot.bin as this generation" 'm4-nix-boot install /run/current-system --efi "$efi" | grep -q "already this generation"'
      check "m4-nix-boot refuses to write on a board that is not J713" '
        before=$(sha256sum "$efi/omarchy/boot.bin")
        ! m4-nix-boot install /run/current-system --efi "$efi" --apply 2>/tmp/err
        grep -q "apple,j713" /tmp/err
        [ "$(sha256sum "$efi/omarchy/boot.bin")" = "$before" ] && [ ! -e "$efi/omarchy/boot.bin.original" ]'
      check "suspend is refused" '! systemctl suspend'
      check "lid close powers off" 'grep -rqs "HandleLidSwitch=poweroff" /etc/systemd/logind.conf /etc/systemd/logind.conf.d'
      check "speaker and headphone drivers are blacklisted" '
        for m in snd_soc_tas2764 snd_soc_tas2770 snd_soc_apple_mca snd_soc_macaudio snd_soc_cs42l84; do
          grep -qs "blacklist $m" /etc/modprobe.d/nixos.conf || exit 1
          ! grep -q "^$m " /proc/modules || exit 1
        done'
      check "the qualified switches are on the kernel command line" '
        for p in maxcpus=10 idle=nop dockchannel_hid.m4_power_v2=1 dockchannel_hid.m4_afe_action=1 pcie_apple.m4_link_diag=1 pcie_apple.m4_keep_clocks=1; do
          grep -qw "$p" /proc/cmdline || exit 1
        done'

      if [ "$fail" = 0 ]; then echo "M4-NIX-SELFTEST DONE result=PASS"; else echo "M4-NIX-SELFTEST DONE result=FAIL"; fi
      systemctl --no-block poweroff
    '';
  };
}

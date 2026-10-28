#!/usr/bin/env bash
# firn-report: read-only hardware report for the J713 runbook.
#   firn-report            one report (save it: firn-report > report.txt)
#   firn-report temps [S]  print CPU and SoC temperatures every S seconds (default 2)
set -uo pipefail

section() { printf '\n== %s ==\n' "$1"; }

temps() {
  for hwmon in /sys/class/hwmon/hwmon*; do
    name=$(cat "$hwmon/name" 2>/dev/null) || continue
    for input in "$hwmon"/temp*_input; do
      [[ -r "$input" ]] || continue
      label=$(cat "${input%_input}_label" 2>/dev/null || basename "$input")
      printf '%-10s %-28s %6.1f C\n' "$name" "$label" "$(awk '{print $1/1000}' "$input")"
    done
  done
}

if [[ "${1:-}" == temps ]]; then
  interval=${2:-2}
  while :; do
    printf '%s\n' "$(date +%T)"
    temps
    sleep "$interval"
  done
fi

section 'system'
date -Is
uname -a
tr '\0' ' ' < /proc/device-tree/compatible; echo
printf 'cmdline: %s\n' "$(cat /proc/cmdline)"
printf 'generation: %s\n' "$(readlink -f /run/current-system)"

section 'failed units'
systemctl --failed --no-legend --plain || true

section 'kernel warnings and errors (this boot)'
journalctl -k -b -p warning --no-pager -q | tail -80

section 'firmware loading'
journalctl -k -b --no-pager -q | grep -iE 'firmware|brcmf' | tail -40
find /run/vendorfw -maxdepth 2 2>/dev/null | head -20

section 'network'
ip -brief link
ip -brief addr
command -v iwctl >/dev/null && iwctl device list 2>/dev/null

section 'CPU frequency'
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
  [[ -d "$policy" ]] || continue
  printf '%s cpus=%s cur=%s min=%s max=%s gov=%s\n' "$(basename "$policy")" \
    "$(cat "$policy/related_cpus")" "$(cat "$policy/scaling_cur_freq")" \
    "$(cat "$policy/scaling_min_freq")" "$(cat "$policy/scaling_max_freq")" \
    "$(cat "$policy/scaling_governor")"
done
printf 'online cpus: %s\n' "$(cat /sys/devices/system/cpu/online)"

section 'temperatures'
temps

section 'battery and power'
for supply in /sys/class/power_supply/*; do
  [[ -d "$supply" ]] || continue
  printf '%s:' "$(basename "$supply")"
  for field in type status capacity online voltage_now current_now temp; do
    [[ -r "$supply/$field" ]] && printf ' %s=%s' "$field" "$(cat "$supply/$field")"
  done
  echo
done

section 'off-profile drivers (must not be loaded)'
for module in snd_soc_tas2764 snd_soc_tas2770 snd_soc_apple_mca snd_soc_macaudio snd_soc_cs42l84; do
  if grep -q "^$module " /proc/modules; then echo "LOADED: $module"; else echo "not loaded: $module"; fi
done

section 'boot.bin'
efi=/boot/efi
if mountpoint -q "$efi"; then
  ls -l "$efi/m1n1/"
  firn-boot inspect "$efi/m1n1/boot.bin"
else
  echo "$efi is not mounted (systemctl status firn-esp)"
fi

section 'storage'
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTUUID,MOUNTPOINTS
df -h / "$efi" 2>/dev/null

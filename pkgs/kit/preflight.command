#!/bin/bash
# Read-only checks before installing.
#   bash preflight.command [GB]   GB for Firn, default 60
set -uo pipefail
kit=$(cd "$(dirname "$0")" && pwd -P)
firn_gb=${1:-60}
[[ "$firn_gb" =~ ^[0-9]+$ ]] || { echo 'Usage: bash preflight.command [GB for Firn, default 60]' >&2; exit 2; }
fail=0 warn=0
ok() { printf 'ok    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }
note() { printf 'WARN  %s\n' "$*"; warn=1; }

version_ge() {
  local i a b
  IFS=. read -ra a <<< "$1"
  IFS=. read -ra b <<< "$2"
  for i in 0 1 2; do
    (( ${a[i]:-0} > ${b[i]:-0} )) && return 0
    (( ${a[i]:-0} < ${b[i]:-0} )) && return 1
  done
  return 0
}

echo 'Firn preflight (read-only)'
if [[ $(uname -s) == Darwin && $(uname -m) == arm64 ]]; then ok 'native arm64 macOS'
else bad 'not native arm64 macOS'; fi

model=$(/usr/sbin/sysctl -n hw.model 2>/dev/null)
if [[ "$model" == Mac16,12 ]]; then ok "model $model (13-inch M4 Air, J713)"
else bad "model $model is not Mac16,12"; fi

macos=$(/usr/bin/sw_vers -productVersion)
if version_ge "$macos" 26.5; then ok "macOS $macos (26.5 or newer)"; else bad "macOS $macos is older than 26.5"; fi
firmware=$(/usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/System Firmware Version/{print $2}')
ok "system firmware $firmware"

# The installer counts decimal GB and keeps 38 GB free in macOS.
G=1000000000
info=$(/usr/sbin/diskutil info /)
bytes() { awk -F'[(]' -v key="$1" '$0 ~ key {print $2; exit}' <<< "$info" | awk '{print $1}'; }
total=$(bytes 'Container Total Space')
free=$(bytes 'Container Free Space')
if [[ -n "$total" && -n "$free" ]]; then
  need=$(( (firn_gb + 38) * G ))
  if (( free >= need )); then
    ok "$(( free / G )) GB free of $(( total / G )) GB in the macOS container"
    echo "      When the installer asks for the new size of macOS, enter $(( (total - firn_gb * G) / G ))GB."
    echo "      That leaves ${firn_gb} GB for Firn."
  else
    bad "$(( free / G )) GB free; ${firn_gb} GB for Firn plus the 38 GB macOS keeps free needs $(( need / G )) GB (or try: bash preflight.command SMALLER-GB)"
  fi
else
  note 'could not read the size of the macOS container'
fi

if /usr/bin/pmset -g batt | grep -q "AC Power"; then ok 'on AC power'; else bad 'not on AC power; connect the charger'; fi

latest=$(/usr/bin/tmutil latestbackup 2>/dev/null)
if [[ -n "$latest" ]]; then ok "latest Time Machine backup: $latest"
else note 'no Time Machine backup found; make and check a full backup before installing'; fi

fv=$(/usr/bin/fdesetup status 2>/dev/null)
ok "FileVault: ${fv:-unknown}"

others=$(/usr/sbin/diskutil list internal | grep -E 'Linux|EFI|Microsoft' | grep -v 'EFI EFI ' )
if [[ -n "$others" ]]; then
  note 'other OS partitions exist on the internal disk; read them before installing:'
  printf '        %s\n' "$others"
else
  ok 'no other Linux or extra EFI partitions on the internal disk'
fi

if [[ -f "$kit/SHA256SUMS" ]]; then
  if (cd "$kit" && /usr/bin/shasum -a 256 -c --quiet SHA256SUMS); then ok 'kit files match SHA256SUMS'
  else bad 'kit files do not match SHA256SUMS'; fi
fi

echo
if (( fail )); then echo 'RESULT: do not install yet (FAIL above).'; exit 1; fi
if (( warn )); then echo 'RESULT: installable, but read the WARN lines first.'; exit 0; fi
echo 'RESULT: ready to install.'

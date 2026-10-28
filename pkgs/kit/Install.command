#!/bin/bash
# Install Firn from this kit. Run it in Terminal on the Air itself.
#   bash Install.command --verify-only   check every file in the kit
#   bash Install.command                 check, then start the installer
set -euo pipefail
kit=$(cd "$(dirname "$0")" && pwd -P)

case "${1:-}" in
  "" | --verify-only) ;;
  *) echo 'Usage: bash Install.command [--verify-only]' >&2; exit 2 ;;
esac

echo 'Checking the kit. The OS package takes a minute; wait for its OK line.'
(cd "$kit" && shasum -a 256 -c SHA256SUMS)
[[ "${1:-}" == --verify-only ]] && exit 0

[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || { echo 'Run this from macOS on the Air.' >&2; exit 1; }
[[ $(/usr/sbin/sysctl -n hw.model) == Mac16,12 ]] ||
  { echo 'Firn supports only the 13-inch M4 MacBook Air (Mac16,12).' >&2; exit 1; }

work=$(mktemp -d /private/tmp/firn-install.XXXXXXXX)
tar -xzf "$kit/installer.tar.gz" -C "$work"
cp "$kit/installer_data.json" "$work/"
echo "Installer files: $work"
echo 'The installer runs as root; enter your password if asked.'
# REPO_BASE is where the installer finds os/<package>. Without REPORT it
# sends no install report.
exec /usr/bin/caffeinate -dis /usr/bin/sudo /usr/bin/env \
  REPO_BASE="$kit" DISTRO=Firn DISTRO_DOCS='GUIDE.md in the installer kit' \
  "$work/install.sh"

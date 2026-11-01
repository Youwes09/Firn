#!/usr/bin/env bash
# Generate the J713 kernel configuration from config/*.config on top of
# allnoconfig. Fails if any requested value does not survive, which
# means a missing dependency or a renamed option. Pass the toolchain the
# kernel is built with, since some options depend on it:
#   make-config.sh KERNEL_TREE OUT [--with FRAGMENT]... [LLVM=1 | CROSS_COMPILE=...]
# --with adds a fragment after config/*.config, such as qemu-virt.config
# for j713-vm.config.
set -euo pipefail

src=$(realpath "$1")
out=$(realpath "$2")
shift 2
fragments=("$(dirname "$(realpath "$0")")"/config/*.config)
while [ "${1-}" = --with ]; do
	fragments+=("$(realpath "$2")")
	shift 2
done
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

log=$(cd "$src" && env ARCH=arm64 "$@" scripts/kconfig/merge_config.sh -n -O "$build" "${fragments[@]}" 2>&1) || { printf '%s\n' "$log" >&2; exit 1; }
if grep -q 'Value requested' <<<"$log"; then
	grep -A2 'Value requested' <<<"$log" >&2
	exit 1
fi
cp "$build/.config" "$out"

#!/usr/bin/env bash
# Regenerate patches/ from the J713 series: one patch per commit of BRANCH
# on top of the mainline commit BASE that default.nix fetches.
#   update-patches.sh KERNEL_CHECKOUT [BRANCH] [BASE]
set -euo pipefail

src=$1
branch=${2:-firn/next}
base=${3:-d89e1d186ec92}
out=$(dirname "$(realpath "$0")")/patches

rm -rf "$out"
git -C "$src" format-patch -q -N --zero-commit --no-signature -o "$out" "$base..$branch"

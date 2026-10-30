#!/usr/bin/env bash
# Regenerate patches/ from a Gravity Linux checkout whose BRANCH merges
# Gravity's replacement/* and bits/* branches onto BASE, then adds Firn's
# commits: one patch per merged branch, then one per Firn commit.
#   update-patches.sh GRAVITY_CHECKOUT [BRANCH] [BASE]
set -euo pipefail

src=$1
branch=${2:-firn/7.3}
base=${3:-d1d4269fcce12}
out=$(dirname "$(realpath "$0")")/patches

rm -rf "$out"
mkdir -p "$out"
n=0
for merge in $(git -C "$src" rev-list --reverse --first-parent --merges "$base..$branch"); do
	n=$((n + 1))
	name=$(git -C "$src" log -1 --format=%s "$merge" | sed -E "s/^Merge remote-tracking branch 'origin\/(.*)' into .*/\1/")
	file=$(printf '%04d-%s.patch' "$n" "${name//\//-}")
	{
		echo "Gravity Linux $name, as merged in $(git -C "$src" rev-parse --short=12 "$merge")."
		echo
		git -C "$src" diff "$merge^1" "$merge"
	} > "$out/$file"
done
last=$(git -C "$src" rev-list -1 --first-parent --merges "$base..$branch")
git -C "$src" format-patch -q -N --no-signature --start-number $((n + 1)) -o "$out" "$last..$branch"

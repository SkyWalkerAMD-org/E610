#!/bin/sh
# Preserve the same exact-ABI driver after Anaconda switches to its live root.
set -eu
root=${1:?Missing Anaconda root}
[ "$root" != / ] && [ -f "$root/etc/os-release" ] || exit 1
src=${0%/*}
/bin/sh "$src/prepare-live.sh" "$root"
k=$(uname -r)
module=$src/drivers/$k/ixgbe.ko
[ -f "$module" ] || exit 1
resolved=$(readlink -f "$root")
dir=$(readlink -f "$root/lib/modules/$k")
case "$dir" in "$resolved"/*) ;; *) exit 1;; esac
[ -d "$dir" ] && [ ! -L "$dir/updates" ] && [ ! -L "$dir/updates/e610" ] || exit 1
mkdir -p "$dir/updates/e610"
[ ! -L "$dir/updates/e610/ixgbe.ko" ] || exit 1
if [ -f "$dir/updates/e610/ixgbe.ko" ]; then cmp -s "$module" "$dir/updates/e610/ixgbe.ko"; fi
cp -p "$module" "$dir/updates/e610/ixgbe.ko"
chroot "$root" /sbin/depmod -a "$k"
selected=$(chroot "$root" /sbin/modinfo -k "$k" -F filename ixgbe)
case "$selected" in */updates/e610/ixgbe.ko) ;; *) echo "E610: unexpected live module $selected" >&2; exit 1;; esac
echo 'E610 Anaconda live driver and installation completion hook ready.'

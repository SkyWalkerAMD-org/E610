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

in_live_root() {
    if command -v chroot >/dev/null 2>&1; then
        chroot "$root" "$@"
        return
    fi
    # EL10 omits chroot from its early initramfs. Use the live image's binary
    # with its own loader and libraries, before entering that same live root.
    # Never substitute the build server's libc or chroot implementation.
    loader=$(readlink -f "$root/lib64/ld-linux-x86-64.so.2")
    case "$loader" in "$resolved"/*) ;; *) return 1;; esac
    [ -x "$loader" ] || return 1
    for candidate in usr/sbin/chroot usr/bin/chroot sbin/chroot bin/chroot; do
        binary=$(readlink -f "$root/$candidate") || continue
        case "$binary" in "$resolved"/*) ;; *) continue;; esac
        [ -x "$binary" ] || continue
        "$loader" --library-path "$root/usr/lib64:$root/lib64" "$binary" "$root" "$@"
        return
    done
    echo 'E610: no usable chroot in the initramfs or Anaconda live root' >&2
    return 1
}
in_live_root /sbin/depmod -a "$k"
selected=$(in_live_root /sbin/modinfo -k "$k" -F filename ixgbe)
case "$selected" in */updates/e610/ixgbe.ko) ;; *) echo "E610: unexpected live module $selected" >&2; exit 1;; esac
echo 'E610 Anaconda live driver and installation completion hook ready.'

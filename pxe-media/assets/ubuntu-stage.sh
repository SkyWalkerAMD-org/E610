#!/bin/sh
# Runs at the end of Ubuntu's native init-bottom, before the live root pivot.
set -eu
root=${1:?Missing live root}
[ "$root" != / ] && [ -f "$root/etc/os-release" ] || exit 1
/bin/sh /ventoy-manual-preload/prepare-live.sh "$root"
/bin/sh /ventoy-e610/prepare-live.sh "$root"
k=$(uname -r)
module=/ventoy-e610/drivers/$k/ixgbe.ko
if [ -f "$module" ]; then
    # After pivot, a reload must still select the same exact-ABI driver.
    dir=$(readlink -f "$root/lib/modules/$k")
    resolved=$(readlink -f "$root")
    case "$dir" in "$resolved"/*) ;; *) exit 1;; esac
    [ -d "$dir" ] && [ ! -L "$dir/updates" ] && [ ! -L "$dir/updates/e610" ] || exit 1
    # Focal's casper mounts a separate read-only kernel modules squashfs here.
    # Preserve that entire tree as the lower layer; only our module/index files
    # go into an in-memory upper layer that survives the live-root pivot.
    if probe=$(mktemp "$dir/.e610-write.XXXXXX" 2>/dev/null); then
        rm -f "$probe"
    else
        [ ! -L "$root/var" ] && [ ! -L "$root/var/lib" ] || exit 1
        overlay=$root/var/lib/ventoy-e610-live-modules-$k
        [ ! -e "$overlay" ] && [ ! -L "$overlay" ] || exit 1
        mkdir -p "$overlay"
        mount -t tmpfs -o mode=0700,size=128M e610-live-modules "$overlay"
        mkdir -p "$overlay/upper" "$overlay/work"
        modprobe overlay
        mount -t overlay overlay -o "lowerdir=$dir,upperdir=$overlay/upper,workdir=$overlay/work" "$dir"
    fi
    mkdir -p "$dir/updates/e610"
    [ ! -L "$dir/updates/e610/ixgbe.ko" ] || exit 1
    if [ -f "$dir/updates/e610/ixgbe.ko" ]; then
        cmp -s "$module" "$dir/updates/e610/ixgbe.ko"
    fi
    cp -p "$module" "$dir/updates/e610/ixgbe.ko"
    chroot "$root" depmod -a "$k"
    selected=$(chroot "$root" modinfo -k "$k" -F filename ixgbe)
    case "$selected" in */updates/e610/ixgbe.ko) ;; *) exit 1;; esac
fi
echo 'E610 Ubuntu live root and installation completion hooks ready.'

#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
fail() {
    echo "E610_CLOUD_MODULE_LOAD_FAIL: $*"
    dmesg
    poweroff -f
    exit 1
}
expected=$(cat /expected-kernel.txt)
[ "$(uname -r)" = "$expected" ] || fail 'kernel mismatch'
ixgbe_module=
while read -r module; do
    echo "Loading $module"
    insmod "$module" || fail "insmod $module"
    case "$module" in
        *-ixgbe.ko) ixgbe_module=$module ;;
    esac
done < /load-order.txt
[ -n "$ixgbe_module" ] || fail 'ixgbe module path missing'
[ -r /proc/slabinfo ] || fail 'slabinfo unavailable'
for cycle in 1 2 3; do
    if [ "$cycle" -gt 1 ]; then
        insmod "$ixgbe_module" || fail "reload cycle=$cycle"
    fi
    lsmod
    grep -q '^ixgbe ' /proc/modules || fail 'ixgbe is not loaded'
    grep -q '^kc_radix_tree_node ' /proc/slabinfo || fail 'compat cache missing'
    rmmod ixgbe || fail 'rmmod ixgbe'
    if grep -q '^ixgbe ' /proc/modules; then
        fail 'ixgbe remains loaded'
    fi
    if grep -q '^kc_radix_tree_node ' /proc/slabinfo; then
        fail 'compat cache leaked after unload'
    fi
    echo "E610_RELOAD_AND_CLEANUP_PASS cycle=$cycle"
done
dmesg
echo "E610_CLOUD_MODULE_LOAD_PASS kernel=$expected"
poweroff -f

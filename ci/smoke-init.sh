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
while read -r module; do
    echo "Loading $module"
    insmod "$module" || fail "insmod $module"
done < /load-order.txt
lsmod
grep -q '^ixgbe ' /proc/modules || fail 'ixgbe is not loaded'
dmesg
rmmod ixgbe || fail 'rmmod ixgbe'
if grep -q '^ixgbe ' /proc/modules; then
    fail 'ixgbe remains loaded'
fi
echo "E610_CLOUD_MODULE_LOAD_PASS kernel=$expected"
poweroff -f

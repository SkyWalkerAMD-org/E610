#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
fail() { echo "E610_SMOKE_FAIL $*"; dmesg; poweroff -f; sleep 60; }
kernel=$(cat /expected-kernel)
kind=$(cat /kind)
[ "$(uname -r)" = "$kernel" ] || fail kernel
while read module; do
  [ "$module" = ixgbe.ko ] && continue
  insmod "/modules/$module" || fail "dependency $module"
done < /load-order.txt
for cycle in 1 2 3; do
  insmod /modules/ixgbe.ko || fail module-load
  if [ "$kind" = external ]; then
    [ "$(cat /sys/module/ixgbe/version)" = 6.4.5 ] || fail version
  fi
  rmmod ixgbe || fail module-unload
  echo "E610_MODULE_CYCLE_PASS $cycle"
done
dmesg
echo "E610_KERNEL_LOAD_PASS kernel=$kernel kind=$kind"
poweroff -f

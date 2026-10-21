#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t securityfs securityfs /sys/kernel/security
mount -t efivarfs efivarfs /sys/firmware/efi/efivars
fail() { echo "E610_SMOKE_FAIL $*"; dmesg; poweroff -f; sleep 60; }
[ "$(uname -r)" = 6.8.0-31-generic ] || fail kernel
sb=$(cat /sys/firmware/efi/efivars/SecureBoot-* | od -An -j4 -N1 -tu1 | tr -d '[:space:]')
echo "E610_SECURE_BOOT_BYTE=$sb"
[ "$sb" -eq 1 ] || fail secureboot
cat /sys/kernel/security/lockdown
grep -q '\[integrity\]\|\[confidentiality\]' /sys/kernel/security/lockdown || fail lockdown
mokutil --test-key /E610-MOK.der || fail enrolled-certificate-check
result=0
untrusted=$(mokutil --test-key /untrusted.der 2>&1) || result=$?
[ "$result" = 1 ] || fail untrusted-certificate-return-code
case "$untrusted" in *'is not enrolled'*) ;; *) fail untrusted-certificate-message ;; esac
echo E610_MOK_CERTIFICATE_CHECK_PASS
while read module; do
  [ "$module" = ixgbe.ko ] && continue
  insmod "/modules/$module" || fail "dependency $module"
done < /load-order.txt
if insmod /unsigned-ixgbe.ko; then fail unsigned-module-was-accepted; fi
echo 'E610_UNSIGNED_MODULE_REJECTED'
for cycle in 1 2 3; do
  insmod /modules/ixgbe.ko || fail signed-module-load
  [ "$(cat /sys/module/ixgbe/version)" = 6.4.5 ] || fail version
  rmmod ixgbe || fail signed-module-unload
  echo "E610_SIGNED_MODULE_CYCLE_PASS $cycle"
done
dmesg
echo 'E610_SECURE_BOOT_LOAD_PASS kernel=6.8.0-31-generic'
poweroff -f

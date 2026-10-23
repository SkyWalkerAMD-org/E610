#!/bin/bash
set -Eeuo pipefail
export LC_ALL=C
kver=5.15.0-78-generic
package=/package
dest=/lib/modules/$kver/updates/e610/ixgbe.ko
hook=/etc/initramfs-tools/hooks/e610-ixgbe-5.15.0-78
image=/boot/initrd.img-$kver
state=/var/lib/e610-ixgbe/ubuntu22-$kver
for deb in /kernel-debs/*.deb; do dpkg-deb -x "$deb" /; done
depmod -a "$kver"
update-initramfs -c -k "$kver"
original_image=$(sha256sum "$image" | awk '{print $1}')
expected=$(sha256sum "$package/ixgbe.ko" | awk '{print $1}')
run() { bash "$package/install.sh" --kernel "$kver" "$@"; }
run --check
test ! -e "$state/latest"
if bash "$package/install.sh" --kernel 5.15.0-999-generic; then exit 1; fi
cp -a "$package" /tmp/corrupt-package
printf corrupt >> /tmp/corrupt-package/ixgbe.ko
if bash /tmp/corrupt-package/install.sh --kernel "$kver"; then exit 1; fi
run
test "$(sha256sum "$dest" | awk '{print $1}')" = "$expected"
test "$(readlink -f "$(modinfo -k "$kver" -n ixgbe)")" = "$(readlink -f "$dest")"
backup=$(readlink -f "$state/latest")
run
test "$(readlink -f "$state/latest")" = "$backup"
test "$(sha256sum "$backup/initrd" | awk '{print $1}')" = "$original_image"
run --rollback
run --rollback
test ! -e "$dest"
test ! -e "$hook"
test "$(sha256sum "$image" | awk '{print $1}')" = "$original_image"
echo E610_INSTALL_ROLLBACK_PASS
# Preserve an existing custom update module and hook.
original_module=$(modinfo -k "$kver" -n ixgbe)
mkdir -p "${dest%/*}"
case "$original_module" in
    *.zst) zstd -dc "$original_module" > "$dest" ;;
    *.xz) xz -dc "$original_module" > "$dest" ;;
    *) cp "$original_module" "$dest" ;;
esac
printf '#!/bin/sh\nexit 0\n' > "$hook"
chmod 755 "$hook"
previous_module=$(sha256sum "$dest" | awk '{print $1}')
previous_hook=$(sha256sum "$hook" | awk '{print $1}')
depmod -a "$kver"
run
backup=$(readlink -f "$state/latest")
cp "$backup/backup.sha256" /tmp/good-backup-sha
echo invalid > "$backup/backup.sha256"
if run --rollback; then exit 1; fi
test "$(sha256sum "$dest" | awk '{print $1}')" = "$expected"
cp /tmp/good-backup-sha "$backup/backup.sha256"
run --rollback
test "$(sha256sum "$dest" | awk '{print $1}')" = "$previous_module"
test "$(sha256sum "$hook" | awk '{print $1}')" = "$previous_hook"
test "$(sha256sum "$image" | awk '{print $1}')" = "$original_image"
echo E610_EXISTING_FILES_PRESERVED
# A real failing initramfs hook exercises the installer's restoration path.
printf '#!/bin/sh\n[ "${1:-}" = prereqs ] && exit 0\nexit 42\n' > /etc/initramfs-tools/hooks/zz-e610-test-fail
chmod 755 /etc/initramfs-tools/hooks/zz-e610-test-fail
if run; then exit 1; fi
test "$(sha256sum "$dest" | awk '{print $1}')" = "$previous_module"
test "$(sha256sum "$hook" | awk '{print $1}')" = "$previous_hook"
test "$(sha256sum "$image" | awk '{print $1}')" = "$original_image"
test "$(cat "$state/latest/status")" = rolled-back
echo E610_FAILED_INITRAMFS_RECOVERY_PASS
echo E610_INSTALLER_TEST_PASS

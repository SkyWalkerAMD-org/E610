#!/bin/bash
set -Eeuo pipefail
export LC_ALL=C
kver=${1:?kernel}
package=/package
. /etc/os-release
if command -v gcc || command -v make; then echo 'Unexpected build tools in offline test'; exit 1; fi
dest=/lib/modules/$kver/updates/e610/ixgbe.ko
state=/var/lib/e610-ixgbe/expanded-$ID-$kver
mkdir -p /lib/modules /boot
cp -a /fixture/lib/modules/"$kver" /lib/modules/
rm -rf -- /lib/modules/"$kver"/updates/e610
depmod -a "$kver"
if [[ $ID == ubuntu ]]; then
    hook=/etc/initramfs-tools/hooks/e610-ixgbe-$kver
    image=/boot/initrd.img-$kver
    cp /fixture/boot/config-"$kver" /boot/
    mkinitramfs -o "$image" "$kver"
else
    hook=/etc/dracut.conf.d/90-e610-$kver.conf
    image=/boot/initramfs-$kver.img
    dracut --force --no-hostonly --kver "$kver" "$image"
fi
original=$(sha256sum "$image" | awk '{print $1}')
expected=$(sha256sum "$package/ixgbe.ko" | awk '{print $1}')
run() { bash "$package/install.sh" --kernel "$kver" "$@"; }
run --check
test ! -e "$state/latest"
if bash "$package/install.sh" --kernel 0.0.0-unsupported; then exit 1; fi
cp -a "$package" /tmp/corrupt-package
printf corrupt >> /tmp/corrupt-package/ixgbe.ko
if bash /tmp/corrupt-package/install.sh --kernel "$kver"; then exit 1; fi
run
test "$(sha256sum "$dest" | awk '{print $1}')" = "$expected"
backup=$(readlink -f "$state/latest")
installed=$(sha256sum "$image" | awk '{print $1}')
run
test "$(readlink -f "$state/latest")" = "$backup"
test "$(sha256sum "$image" | awk '{print $1}')" = "$installed"
run --rollback
run --rollback
test ! -e "$dest"
test ! -e "$hook"
test "$(sha256sum "$image" | awk '{print $1}')" = "$original"
echo E610_INSTALL_ROLLBACK_PASS
original_module=$(modinfo -k "$kver" -n ixgbe)
mkdir -p "${dest%/*}"
case "$original_module" in
    *.zst) zstd -dc "$original_module" > "$dest" ;;
    *.xz) xz -dc "$original_module" > "$dest" ;;
    *) cp "$original_module" "$dest" ;;
esac
if [[ $ID == ubuntu ]]; then printf '#!/bin/sh\nexit 0\n' > "$hook"; else echo '# previous config' > "$hook"; fi
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
test "$(sha256sum "$image" | awk '{print $1}')" = "$original"
echo E610_EXISTING_FILES_PRESERVED
if [[ $ID == ubuntu ]]; then
    printf '#!/bin/sh\n[ "${1:-}" = prereqs ] && exit 0\nexit 42\n' > /etc/initramfs-tools/hooks/zz-e610-test-fail
    chmod 755 /etc/initramfs-tools/hooks/zz-e610-test-fail
else
    mkdir -p /usr/lib/dracut/modules.d/99e610fail
    printf '#!/bin/bash\ncheck() { return 0; }\ndepends() { return 0; }\ninstall() { exit 42; }\n' > /usr/lib/dracut/modules.d/99e610fail/module-setup.sh
    chmod 755 /usr/lib/dracut/modules.d/99e610fail/module-setup.sh
fi
if run; then exit 1; fi
test "$(sha256sum "$dest" | awk '{print $1}')" = "$previous_module"
test "$(sha256sum "$hook" | awk '{print $1}')" = "$previous_hook"
test "$(sha256sum "$image" | awk '{print $1}')" = "$original"
test "$(cat "$state/latest/status")" = rolled-back
echo E610_FAILED_INITRAMFS_RECOVERY_PASS
echo "E610_INSTALLER_TEST_PASS kernel=$kver"

#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
: "${KVER:?}"
[[ -f /.dockerenv && $EUID == 0 ]]
cache=/opt/e610-offline/centos7.9-r2
runfile=/media/E610-CentOS7.9-adaptation-r2.run
dest=/lib/modules/$KVER/updates/drivers/net/ethernet/intel/ixgbe/ixgbe.ko
state=/var/lib/e610-ixgbe/$KVER
image=/boot/initramfs-$KVER.img
printf 'hostonly="no"\n' > /etc/dracut.conf.d/e610-media-test.conf
dracut --force --no-hostonly --kver "$KVER" --add-drivers ixgbe "$image"
baseline=$(sha256sum "$image" | awk '{print $1}')
! command -v make
! command -v gcc
(cd /media && sha256sum -c MEDIA-SHA256SUMS)
cp "$runfile" /tmp/corrupt.run
printf corrupt >> /tmp/corrupt.run
if bash /tmp/corrupt.run --kernel "$KVER"; then exit 1; fi
test ! -e "$dest"
test ! -e "$cache"
if bash /media/install.sh --kernel 3.10.0-unvalidated.el7.x86_64; then exit 1; fi
test ! -e "$dest"
bash /media/install.sh --kernel "$KVER" --check
test ! -e "$dest"
bash /media/install.sh --kernel "$KVER"
module=$cache/ixgbe-6.4.5-$KVER/ixgbe.ko
test "$(sha256sum "$dest" | awk '{print $1}')" = "$(sha256sum "$module" | awk '{print $1}')"
test "$(readlink -f "$(modinfo -k "$KVER" -n ixgbe)")" = "$(readlink -f "$dest")"
embedded=$(lsinitrd "$image" | awk '$NF ~ /updates\/drivers\/net\/ethernet\/intel\/ixgbe\/ixgbe.ko$/ {print $NF}')
[[ -n $embedded && $embedded != *$'\n'* ]]
lsinitrd -f "$embedded" "$image" > /tmp/embedded-ixgbe.ko
for field in version vermagic srcversion; do
    test "$(modinfo -F "$field" /tmp/embedded-ixgbe.ko)" = "$(modinfo -F "$field" "$module")"
done
backup=$(readlink -f "$state/latest")
test "$(sha256sum "$backup/initramfs" | awk '{print $1}')" = "$baseline"
(cd /tmp && bash "$runfile" --kernel "$KVER")
test "$(readlink -f "$state/latest")" = "$backup"
cp "$cache/install.sh" /tmp/good-installer
printf '\n# altered\n' >> "$cache/install.sh"
if bash "$runfile" --kernel "$KVER"; then exit 1; fi
cp /tmp/good-installer "$cache/install.sh"
(cd /tmp && bash "$cache/install.sh" --kernel "$KVER" --check)
(cd /tmp && bash "$cache/uninstall.sh" --kernel "$KVER")
test ! -e "$dest"
test "$(sha256sum "$image" | awk '{print $1}')" = "$baseline"
test -z "$(find /opt/e610-offline -maxdepth 1 -name '.stage.*' -print -quit)"
printf 'E610_MEDIA_TEST_PASS kernel=%s\n' "$KVER"

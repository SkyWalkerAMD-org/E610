#!/bin/bash
set -Eeuo pipefail
export LC_ALL=C
kver=6.8.0-31-generic
cache=/opt/e610-offline/ubuntu24-6.8.0-31-r1
runfile=/media/E610-Ubuntu24.04-6.8.0-31-r1.run
dest=/lib/modules/$kver/updates/e610/ixgbe.ko
state=/var/lib/e610-ixgbe/ubuntu24-$kver
image=/boot/initrd.img-$kver
for deb in /kernel-debs/*.deb; do dpkg-deb -x "$deb" /; done
depmod -a "$kver"
update-initramfs -c -k "$kver"
original_image=$(sha256sum "$image" | awk '{print $1}')
! command -v make
! command -v gcc
(cd /media && sha256sum -c MEDIA-SHA256SUMS)
# A damaged self-extracting file must be rejected before installation.
cp "$runfile" /tmp/corrupt.run
printf corrupt >> /tmp/corrupt.run
if bash /tmp/corrupt.run --kernel "$kver"; then exit 1; fi
test ! -e "$dest"
test ! -e "$cache"
# Wrong-kernel rejection is retained through the new launcher.
if bash /media/install.sh --kernel 6.8.0-99-generic; then exit 1; fi
test ! -e "$dest"
bash /media/install.sh --kernel "$kver" --check
test ! -e "$dest"
# Install directly from the mounted read-only ISO with networking disabled.
bash /media/install.sh --kernel "$kver"
test "$(sha256sum "$dest" | awk '{print $1}')" = 846e8c45328507d3474019611e5ce4f1c40a7f20875b2b05c4645a15358ca9e1
test "$(sha256sum "$cache/E610-MOK.der" | awk '{print $1}')" = 895376179044eb32c24da6c6df6c3f0b94c0650c030dc54797012bf0a6adde57
backup=$(readlink -f "$state/latest")
mkdir /tmp/other-working-directory
(cd /tmp/other-working-directory && bash "$runfile" --kernel "$kver")
test "$(readlink -f "$state/latest")" = "$backup"
test "$(sha256sum "$backup/initrd" | awk '{print $1}')" = "$original_image"
# An altered cached copy must not be silently overwritten or executed.
cp "$cache/install.sh" /tmp/good-installer
printf '\n# altered\n' >> "$cache/install.sh"
if bash "$runfile" --kernel "$kver"; then exit 1; fi
cp /tmp/good-installer "$cache/install.sh"
# The persistent entry point is self-contained; rollback does not need the ISO.
(cd /tmp && bash "$cache/install.sh" --kernel "$kver" --check)
(cd /tmp && bash "$cache/install.sh" --kernel "$kver" --rollback)
test ! -e "$dest"
test "$(sha256sum "$image" | awk '{print $1}')" = "$original_image"
test -z "$(find /opt/e610-offline -maxdepth 1 -name '.stage.*' -print -quit)"
echo E610_MEDIA_INSTALL_ROLLBACK_PASS
echo E610_MEDIA_TEST_PASS

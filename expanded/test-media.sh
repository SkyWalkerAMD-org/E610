#!/bin/bash
set -Eeuo pipefail
export LC_ALL=C
kver=${1:?kernel}
expected=${2:?expected module sha or native}
. /etc/os-release
if command -v gcc || command -v make; then exit 1; fi
mkdir -p /lib/modules /boot /var/lock
if [[ $ID != centos ]]; then
    cp -a /fixture/lib/modules/"$kver" /lib/modules/
    depmod -a "$kver"
fi
if [[ $ID == ubuntu ]]; then
    image=/boot/initrd.img-$kver
    cp /fixture/boot/config-"$kver" /boot/
    mkinitramfs -o "$image" "$kver"
else
    image=/boot/initramfs-$kver.img
    dracut --force --no-hostonly --kver "$kver" "$image"
fi
original=$(sha256sum "$image" | awk '{print $1}')
cd /media
sha256sum --status -c SHA256SUMS
run=/media/E610-MultiOS-6.4.5-r2.run
cache=/opt/e610-offline/multios-6.4.5-r2
bash "$run" --list
test ! -e "$cache"
cp "$run" /tmp/corrupt.run
printf corrupt >> /tmp/corrupt.run
if bash /tmp/corrupt.run --kernel "$kver" --check; then exit 1; fi
test ! -e "$cache"
if bash /media/install.sh --kernel 0.0.0-unsupported; then exit 1; fi
cp /etc/os-release /tmp/os-release.original
printf 'ID=debian\nVERSION_ID=12\n' > /etc/os-release
if bash /media/install.sh --kernel "$kver" --check; then exit 1; fi
cp /tmp/os-release.original /etc/os-release
mkdir /tmp/extracted
tar -xzf /release/E610-MultiOS-6.4.5-r2.tar.gz -C /tmp/extracted
bash /tmp/extracted/E610-MultiOS-6.4.5-r2/install.sh --kernel "$kver" --check
bash /media/install.sh --kernel "$kver" --check
test "$(sha256sum "$image" | awk '{print $1}')" = "$original"
if [[ $expected == native ]]; then
    bash /media/install.sh --kernel "$kver" | tee /tmp/native.log
    grep -q "E610_NATIVE_SUPPORT kernel=$kver" /tmp/native.log
    test "$(sha256sum "$image" | awk '{print $1}')" = "$original"
    echo "E610_MEDIA_TEST_PASS kernel=$kver native"
    exit 0
fi
# For existing releases, install the original standalone package first. The
# expanded wrapper must reuse its original backup, certificate and module.
case "$kver" in
  5.15.0-78-generic) legacy=E610-Ubuntu22.04.3-5.15.0-78-r1.run; state=/var/lib/e610-ixgbe/ubuntu22-$kver ;;
  6.8.0-31-generic) legacy=E610-Ubuntu24.04-6.8.0-31-r1.run; state=/var/lib/e610-ixgbe/ubuntu24-$kver ;;
  3.10.*) legacy=E610-CentOS7.9-adaptation-r2.run; state=/var/lib/e610-ixgbe/$kver ;;
  *) legacy=; state=/var/lib/e610-ixgbe/expanded-$ID-$kver ;;
esac
if [[ -n $legacy ]]; then
    bash "$cache/payloads/$legacy" --kernel "$kver"
    saved_backup=$(readlink -f "$state/latest")
fi
bash /media/install.sh --kernel "$kver"
dest=$(modinfo -k "$kver" -n ixgbe)
test "$(sha256sum "$dest" | awk '{print $1}')" = "$expected"
backup=$(readlink -f "$state/latest")
[[ -z $legacy ]] || test "$backup" = "$saved_backup"
installed=$(sha256sum "$image" | awk '{print $1}')
bash "$run" --kernel "$kver"
test "$(readlink -f "$state/latest")" = "$backup"
test "$(sha256sum "$image" | awk '{print $1}')" = "$installed"
cp "$cache/install.sh" /tmp/good-dispatch
printf corrupt >> "$cache/install.sh"
if bash "$run" --kernel "$kver" --check; then exit 1; fi
cp /tmp/good-dispatch "$cache/install.sh"
bash "$cache/install.sh" --kernel "$kver" --rollback
test "$(sha256sum "$image" | awk '{print $1}')" = "$original"
test -z "$(find /opt/e610-offline -maxdepth 1 -name '.stage.*' -print)"
echo "E610_MEDIA_TEST_PASS kernel=$kver external"

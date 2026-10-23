#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail
export LC_ALL=C
work=$(realpath -m "${1:?work directory}")
out=$(realpath -m "${2:?output directory}")
kernel=5.15.0-78-generic
mkdir -p "$work" "$out" "$work/kernel" "$work/debs" "$work/headers" "$work/header-debs" "$work/mok-debs"
exec > >(tee "$out/build.log") 2>&1
iso=$work/ubuntu-22.04.3-live-server-amd64.iso
curl --fail --location --retry 3 -o "$iso" https://old-releases.ubuntu.com/releases/22.04.3/ubuntu-22.04.3-live-server-amd64.iso
echo "a4acfda10b18da50e2ec50ccaf860d7f20b389df8765611142305c0e911d16fd  $iso" | sha256sum -c -
extract() { xorriso -osirrox on -indev "$iso" -extract "$1" "$2"; }
for name in linux-headers-5.15.0-78_5.15.0-78.85_all.deb linux-headers-5.15.0-78-generic_5.15.0-78.85_amd64.deb; do
    extract "/pool/main/l/linux/$name" "$work/header-debs/$name"
    dpkg-deb -x "$work/header-debs/$name" "$work/headers"
    dpkg-deb -f "$work/header-debs/$name" Package Version >> "$out/header-packages.txt"
done
extract /pool/main/l/linux-signed/linux-image-5.15.0-78-generic_5.15.0-78.85_amd64.deb "$work/debs/linux-image.deb"
extract /pool/main/l/linux/linux-modules-5.15.0-78-generic_5.15.0-78.85_amd64.deb "$work/debs/linux-modules.deb"
extract /pool/main/l/linux/linux-modules-extra-5.15.0-78-generic_5.15.0-78.85_amd64.deb "$work/debs/linux-modules-extra.deb"
extract /pool/main/m/mokutil/mokutil_0.6.0-2~22.04.1_amd64.deb "$work/mok-debs/mokutil.deb"
for deb in "$work/debs/"*.deb; do dpkg-deb -x "$deb" "$work/kernel"; done
(cd "$work" && sha256sum debs/*.deb header-debs/*.deb mok-debs/*.deb) > "$out/kernel-packages.sha256"
curl --fail --location --retry 3 -o "$work/ixgbe-6.4.5.tar.gz" \
  https://github.com/intel/ethernet-linux-ixgbe/releases/download/v6.4.5/ixgbe-6.4.5.tar.gz
echo "8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4  $work/ixgbe-6.4.5.tar.gz" | sha256sum -c -
tar -xzf "$work/ixgbe-6.4.5.tar.gz" -C "$work"
gcc-11 --version | head -1
headers=$work/headers/usr/src/linux-headers-$kernel
make -C "$work/ixgbe-6.4.5/src" -j2 CC=gcc-11 BUILD_KERNEL="$kernel" KSRC="$headers"
cp "$work/ixgbe-6.4.5/src/ixgbe.ko" "$work/unsigned-ixgbe.ko"
strip --strip-debug "$work/unsigned-ixgbe.ko"
cp "$work/unsigned-ixgbe.ko" "$out/ixgbe.ko"
test "$(modinfo -F vermagic "$out/ixgbe.ko" | cut -d ' ' -f1)" = "$kernel"
test "$(modinfo -F version "$out/ixgbe.ko")" = 6.4.5
for id in 57AE 57AF 57B0 57B1 57B2; do
  modinfo -F alias "$out/ixgbe.ko" | grep "v00008086d0000$id"
done
# This one-release private key is never uploaded, committed, or distributed.
umask 077
trap 'rm -f "$work/release-signing.key"' EXIT
openssl req -new -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
  -subj '/CN=E610 Ubuntu 22.04.3 ixgbe 6.4.5 r1/' \
  -addext 'basicConstraints=critical,CA:FALSE' \
  -addext 'keyUsage=critical,digitalSignature' \
  -addext 'extendedKeyUsage=codeSigning,1.3.6.1.4.1.2312.16.1.2' \
  -keyout "$work/release-signing.key" -out "$work/release-signing.pem"
openssl x509 -in "$work/release-signing.pem" -outform DER -out "$out/E610-MOK.der"
"$headers/scripts/sign-file" sha256 \
  "$work/release-signing.key" "$out/E610-MOK.der" "$out/ixgbe.ko"
rm -f "$work/release-signing.key"
umask 022
chmod 644 "$out/ixgbe.ko" "$out/E610-MOK.der"
openssl x509 -inform DER -in "$out/E610-MOK.der" -noout -subject -dates -fingerprint -sha256 | tee "$out/certificate.txt"
modinfo "$out/ixgbe.ko" > "$out/modinfo.txt"
(cd "$out" && sha256sum ixgbe.ko E610-MOK.der > payload.sha256)
# Use only the signed kernel and modules extracted from the hash-pinned original ISO.
install -D -m 644 "$out/ixgbe.ko" "$work/kernel/lib/modules/$kernel/updates/ixgbe.ko"
depmod -b "$work/kernel" -a "$kernel"
modprobe -d "$work/kernel" -S "$kernel" --show-depends ixgbe > "$out/load-order.txt"
cp "$work/ixgbe-6.4.5.tar.gz" "$out/ixgbe-6.4.5.tar.gz"
printf 'E610_UBUNTU_BUILD_PASS kernel=%s\n' "$kernel"

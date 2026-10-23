#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail
export LC_ALL=C
work=$(realpath -m "${1:?work directory}")
out=$(realpath -m "${2:?output directory}")
kernel=6.8.0-31-generic
mkdir -p "$work" "$out" "$work/kernel" "$work/debs"
exec > >(tee "$out/build.log") 2>&1
curl --fail --location --retry 3 -o "$work/ixgbe-6.4.5.tar.gz" \
  https://github.com/intel/ethernet-linux-ixgbe/releases/download/v6.4.5/ixgbe-6.4.5.tar.gz
echo "8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4  $work/ixgbe-6.4.5.tar.gz" | sha256sum -c -
tar -xzf "$work/ixgbe-6.4.5.tar.gz" -C "$work"
gcc-13 --version | head -1
dpkg-query -W 'linux-headers-6.8.0-31*' | tee "$out/header-packages.txt"
make -C "$work/ixgbe-6.4.5/src" -j2 CC=gcc-13 BUILD_KERNEL="$kernel" KSRC="/usr/src/linux-headers-$kernel"
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
openssl req -new -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
  -subj '/CN=E610 Ubuntu 24.04 ixgbe 6.4.5 r1/' \
  -addext 'basicConstraints=critical,CA:FALSE' \
  -addext 'keyUsage=critical,digitalSignature' \
  -addext 'extendedKeyUsage=codeSigning,1.3.6.1.4.1.2312.16.1.2' \
  -keyout "$work/release-signing.key" -out "$work/release-signing.pem"
openssl x509 -in "$work/release-signing.pem" -outform DER -out "$out/E610-MOK.der"
/usr/src/linux-headers-$kernel/scripts/sign-file sha256 \
  "$work/release-signing.key" "$out/E610-MOK.der" "$out/ixgbe.ko"
rm -f "$work/release-signing.key"
umask 022
chmod 644 "$out/ixgbe.ko" "$out/E610-MOK.der"
openssl x509 -inform DER -in "$out/E610-MOK.der" -noout -subject -dates -fingerprint -sha256 | tee "$out/certificate.txt"
modinfo "$out/ixgbe.ko" > "$out/modinfo.txt"
(cd "$out" && sha256sum ixgbe.ko E610-MOK.der > payload.sha256)
# Download, authenticate through APT metadata, and extract; do not install a kernel on the runner.
(cd "$work/debs" && apt-get download "linux-image-$kernel=6.8.0-31.31" "linux-modules-$kernel=6.8.0-31.31")
for deb in "$work/debs/"*.deb; do dpkg-deb -x "$deb" "$work/kernel"; done
sha256sum "$work/debs/"*.deb | sed "s|$work/debs/||" > "$out/kernel-packages.sha256"
install -D -m 644 "$out/ixgbe.ko" "$work/kernel/lib/modules/$kernel/updates/ixgbe.ko"
depmod -b "$work/kernel" -a "$kernel"
modprobe -d "$work/kernel" -S "$kernel" --show-depends ixgbe > "$out/load-order.txt"
cp "$work/ixgbe-6.4.5.tar.gz" "$out/ixgbe-6.4.5.tar.gz"
printf 'E610_UBUNTU_BUILD_PASS kernel=%s\n' "$kernel"

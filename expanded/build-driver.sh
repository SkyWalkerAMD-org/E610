#!/bin/bash
# Runs in an Ubuntu runner or an appropriate Rocky build container.
set -Eeuo pipefail
export LC_ALL=C
work=$(realpath "${1:?work}")
out=$(realpath "${2:?out}")
kver=${3:?kernel}
headers=$(realpath "${4:?headers}")
compiler=${5:-gcc}
mkdir -p "$out"
exec > >(tee "$out/build.log") 2>&1
tar -xzf "$work/ixgbe-6.4.5.tar.gz" -C "$work"
make -C "$work/ixgbe-6.4.5/src" -j2 CC="$compiler" BUILD_KERNEL="$kver" KSRC="$headers"
cp "$work/ixgbe-6.4.5/src/ixgbe.ko" "$work/unsigned-ixgbe.ko"
strip --strip-debug "$work/unsigned-ixgbe.ko"
cp "$work/unsigned-ixgbe.ko" "$out/ixgbe.ko"
test "$(modinfo -F vermagic "$out/ixgbe.ko" | cut -d ' ' -f1)" = "$kver"
test "$(modinfo -F version "$out/ixgbe.ko")" = 6.4.5
for id in 57AE 57AF 57B0 57B1 57B2; do modinfo -F alias "$out/ixgbe.ko" | grep "v00008086d0000$id"; done
umask 077
trap 'rm -f "$work/release-signing.key"' EXIT
openssl req -new -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
  -subj "/CN=E610 MultiOS r2 $kver/" \
  -addext 'basicConstraints=critical,CA:FALSE' \
  -addext 'keyUsage=critical,digitalSignature' \
  -addext 'subjectKeyIdentifier=hash' \
  -addext 'extendedKeyUsage=codeSigning,1.3.6.1.4.1.2312.16.1.2' \
  -keyout "$work/release-signing.key" -out "$work/release-signing.pem"
openssl x509 -in "$work/release-signing.pem" -outform DER -out "$out/E610-MOK.der"
"$headers/scripts/sign-file" sha256 "$work/release-signing.key" "$out/E610-MOK.der" "$out/ixgbe.ko"
rm -f "$work/release-signing.key"
chmod 644 "$out/ixgbe.ko" "$out/E610-MOK.der"
modinfo "$out/ixgbe.ko" > "$out/modinfo.txt"
openssl x509 -inform DER -in "$out/E610-MOK.der" -noout -subject -dates -fingerprint -sha256 > "$out/certificate.txt"
(cd "$out" && sha256sum ixgbe.ko E610-MOK.der > payload.sha256)
echo "E610_BUILD_PASS kernel=$kver"

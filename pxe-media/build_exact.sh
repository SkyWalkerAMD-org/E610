#!/bin/bash
# Run only inside the disposable build VM, never on a deployment host.
set -Eeuo pipefail
export LC_ALL=C
work=$(realpath "${1:?work}")
kver=${2:?kernel}
compiler=${3:?compiler}
headers=${4:?headers}
[[ -f /root/E610-DISPOSABLE-BUILDER ]] || { echo 'Disposable builder marker missing'; exit 1; }
cd "$work"
mkdir -p output
exec > >(tee output/build.log) 2>&1
trap 'rc=$?; rm -f release-signing.key; printf "%s\n" "$rc" > output/exit-code' EXIT
printf 'kernel=%s\ncompiler=%s\n' "$kver" "$compiler"
"$compiler" --version | head -1
for rpm in ./*.rpm; do
    [[ -f $rpm ]] || continue
    rpm2cpio "$rpm" | (cd /; cpio -idm --quiet)
done
for deb in ./*.deb; do
    [[ -f $deb ]] || continue
    if command -v dpkg-deb >/dev/null; then dpkg-deb -x "$deb" /
    else
        member=$(ar t "$deb" | awk '/^data.tar/ {print; exit}')
        case "$member" in
            *.xz) ar p "$deb" "$member" | xz -dc | tar -x -C / ;;
            *.gz) ar p "$deb" "$member" | gzip -dc | tar -x -C / ;;
            *.zst) ar p "$deb" "$member" | zstd -dc | tar -x -C / ;;
            *.tar) ar p "$deb" "$member" | tar -x -C / ;;
            *) echo "Unsupported Debian payload: $member"; exit 1 ;;
        esac
    fi
done
if [[ -f headers-root.tar.gz ]]; then tar -xzf headers-root.tar.gz -C /; fi
[[ -s "$headers/Module.symvers" ]]
printf '%s\n' '8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4  ixgbe-6.4.5.tar.gz' | sha256sum -c -
tar -xzf ixgbe-6.4.5.tar.gz
if [[ $kver == 3.10.* ]]; then
    for p in patches/000[1-4]-*.patch patches/0006-*.patch; do patch --batch --fuzz=0 -d ixgbe-6.4.5 -p1 < "$p"; done
else
    patch --batch --fuzz=0 -d ixgbe-6.4.5 -p1 < patches/0005-old-copy-attribute.patch
fi
source_headers=$headers
if [[ $kver == *-amd64 ]]; then
    source_headers=${headers%-amd64}-common
    [[ -f "$source_headers/include/linux/netdevice.h" ]]
fi
make -C ixgbe-6.4.5/src -j4 CC="$compiler" BUILD_KERNEL="$kver" KSRC="$source_headers" KOBJ="$headers"
cp ixgbe-6.4.5/src/ixgbe.ko output/ixgbe.ko
strip --strip-debug output/ixgbe.ko
[[ $(modinfo -F vermagic output/ixgbe.ko | cut -d' ' -f1) == "$kver" ]]
[[ $(modinfo -F version output/ixgbe.ko) == 6.4.5 ]]
for id in 57AE 57AF 57B0 57B1 57B2; do modinfo -F alias output/ixgbe.ko | grep -q "v00008086d0000$id"; done
umask 077
cat > signing.cnf <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=E610 installation media $kver
[ext]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
extendedKeyUsage=codeSigning,1.3.6.1.4.1.2312.16.1.2
EOF
openssl req -new -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 -config signing.cnf -keyout release-signing.key -out release-signing.pem > output/signing.log 2>&1
openssl x509 -in release-signing.pem -outform DER -out output/E610-MOK.der
signer=$headers/scripts/sign-file
# The original Ubuntu 20.04 sign-file links OpenSSL 1.1. Prefer the installed
# build VM's ABI-compatible signing utility, without changing target headers.
if command -v kmodsign >/dev/null; then signer=$(command -v kmodsign); fi
if [[ -n ${E610_SIGN_FILE:-} ]]; then signer=$E610_SIGN_FILE; fi
"$signer" sha256 release-signing.key output/E610-MOK.der output/ixgbe.ko
rm -f release-signing.key
chmod 644 output/ixgbe.ko output/E610-MOK.der
modinfo output/ixgbe.ko > output/modinfo.txt
cp ixgbe-6.4.5/src/kcompat_generated_defs.h output/
(cd output; sha256sum ixgbe.ko E610-MOK.der > SHA256SUMS)
printf 'E610_BUILD_PASS kernel=%s\n' "$kver"

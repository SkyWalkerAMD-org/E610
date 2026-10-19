#!/bin/bash
# Build only; never install a driver on the build host.
set -Eeuo pipefail
export LC_ALL=C
if [ "$#" != 3 ]; then
    echo 'Usage: build_module.sh ORIGINAL_UBUNTU_ISO IXGBE_6.4.5_TAR_GZ NEW_WORK_DIRECTORY' >&2
    exit 2
fi
iso=$(realpath "$1")
source_archive=$(realpath "$2")
work=$(realpath -m "$3")
test ! -e "$work" || { echo 'Work directory must not exist' >&2; exit 1; }
printf '%s  %s\n' a4acfda10b18da50e2ec50ccaf860d7f20b389df8765611142305c0e911d16fd "$iso" | sha256sum -c -
printf '%s  %s\n' 8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4 "$source_archive" | sha256sum -c -
mkdir -p "$work/headers" "$work/packages" "$work/output"
exec > >(tee "$work/output/build.log") 2>&1
kernel=5.15.0-78-generic
for deb in linux-headers-5.15.0-78_5.15.0-78.85_all.deb linux-headers-5.15.0-78-generic_5.15.0-78.85_amd64.deb; do
    xorriso -osirrox on -indev "$iso" -extract "/pool/main/l/linux/$deb" "$work/packages/$deb"
    ar p "$work/packages/$deb" data.tar.zst | zstd -d | tar -x -C "$work/headers"
done
tar -xzf "$source_archive" -C "$work"
gcc --version > "$work/output/compiler.txt"
make -C "$work/ixgbe-6.4.5/src" -j4 BUILD_KERNEL="$kernel" KSRC="$work/headers/usr/src/linux-headers-$kernel"
cp "$work/ixgbe-6.4.5/src/ixgbe.ko" "$work/output/ixgbe.ko"
modinfo "$work/output/ixgbe.ko" | tee "$work/output/modinfo.txt"
test "$(modinfo -F vermagic "$work/output/ixgbe.ko" | cut -d ' ' -f 1)" = "$kernel"
test "$(modinfo -F version "$work/output/ixgbe.ko")" = 6.4.5
for id in 57AE 57AF 57B0 57B1 57B2; do
    modinfo -F alias "$work/output/ixgbe.ko" | grep "v00008086d0000$id"
done
(cd "$work/output" && sha256sum ixgbe.ko > SHA256SUMS)
printf 'E610_UBUNTU_BUILD_PASS kernel=%s\n' "$kernel"

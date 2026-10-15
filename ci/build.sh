#!/bin/bash
set -Eeuo pipefail
export LC_ALL=C
: "${KVER:?KVER is required}"
out=/output
mkdir -p "$out" "$out/modules"
exec > >(tee "$out/build.log") 2>&1
trap 'rc=$?; printf "exit_code=%s\n" "$rc" > /output/build-status.txt' EXIT

printf '%s\n' '8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4  /input/ixgbe-6.4.5.tar.gz' | sha256sum -c -
{
    cat /etc/centos-release
    printf 'target_kernel=%s\n' "$KVER"
    printf 'container_host_kernel=%s\n' "$(uname -r)"
    gcc --version
    rpm -q gcc make binutils kernel kernel-devel
} | tee "$out/environment.txt"
test -s "/usr/src/kernels/$KVER/Module.symvers"
tar -xzf /input/ixgbe-6.4.5.tar.gz
for patchfile in /input/patches/*.patch; do
    test -f "$patchfile" || continue
    patch --batch --fuzz=0 -d ixgbe-6.4.5 -p1 < "$patchfile"
    sha256sum "$patchfile" >> "$out/patches.sha256"
done
cp "/usr/src/kernels/$KVER/.config" "$out/kernel.config"
make -C ixgbe-6.4.5/src -j2 BUILD_KERNEL="$KVER" KSRC="/usr/src/kernels/$KVER"
cp ixgbe-6.4.5/src/kcompat_generated_defs.h "$out/"
cp ixgbe-6.4.5/src/ixgbe.ko "$out/ixgbe.ko"
modinfo "$out/ixgbe.ko" | tee "$out/modinfo.txt"
test "$(modinfo -F vermagic "$out/ixgbe.ko" | awk '{print $1}')" = "$KVER"
test "$(modinfo -F version "$out/ixgbe.ko")" = '6.4.5'
for pci_id in 57AE 57AF 57B0 57B1 57B2; do
    modinfo -F alias "$out/ixgbe.ko" | grep -q "v00008086d0000${pci_id}"
done
nm -u "$out/ixgbe.ko" > "$out/imported-symbols.txt"
sha256sum "$out/ixgbe.ko" > "$out/module.sha256"

# Install only inside this disposable build container to resolve dependencies.
install -D -m 644 "$out/ixgbe.ko" "/lib/modules/$KVER/updates/ixgbe.ko"
depmod -a "$KVER"
modprobe --set-version "$KVER" --show-depends ixgbe | tee "$out/dependencies.txt"
index=0
: > "$out/load-order.txt"
while read -r verb module args; do
    test "$verb" = insmod || continue
    index=$((index + 1))
    name=$(printf '%02d-%s' "$index" "$(basename "${module%.xz}")")
    case "$module" in
        *.xz) xz -dc "$module" > "$out/modules/$name" ;;
        *.gz) gzip -dc "$module" > "$out/modules/${name%.gz}"; name=${name%.gz} ;;
        *) cp "$module" "$out/modules/$name" ;;
    esac
    printf '/modules/%s\n' "$name" >> "$out/load-order.txt"
done < "$out/dependencies.txt"
test "$index" -gt 0
grep -q 'ixgbe.ko$' "$out/load-order.txt"
cp "/boot/vmlinuz-$KVER" "$out/vmlinuz"
printf '%s\n' "$KVER" > "$out/expected-kernel.txt"
printf 'E610_BUILD_PASS kernel=%s\n' "$KVER"

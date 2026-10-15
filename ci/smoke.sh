#!/bin/bash
set -Eeuo pipefail
export LC_ALL=C
out=$(realpath "${1:?Usage: smoke.sh OUTPUT_DIR}")
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root"/{bin,dev,proc,sys,modules}
cp /usr/bin/busybox "$root/bin/busybox"
for cmd in sh mount insmod rmmod lsmod uname dmesg poweroff cat grep; do
    ln -s busybox "$root/bin/$cmd"
done
cp "$script_dir/smoke-init.sh" "$root/init"
chmod 755 "$root/init"
cp "$out"/modules/*.ko "$root/modules/"
cp "$out/load-order.txt" "$out/expected-kernel.txt" "$root/"
sudo mknod "$root/dev/console" c 5 1
sudo mknod "$root/dev/null" c 1 3
(cd "$root" && find . -print0 | cpio --null -o --format=newc --owner=0:0) | gzip -1 > "$out/smoke-initramfs.cpio.gz"
timeout 180 qemu-system-x86_64 \
    -machine pc,accel=tcg -cpu max -smp 2 -m 768 \
    -display none -serial stdio -monitor none -nic none -no-reboot \
    -kernel "$out/vmlinuz" -initrd "$out/smoke-initramfs.cpio.gz" \
    -append 'console=ttyS0 rdinit=/init panic=1' 2>&1 | tee "$out/boot.log"
grep -q '^E610_CLOUD_MODULE_LOAD_PASS kernel=' "$out/boot.log"
! grep -q 'E610_CLOUD_MODULE_LOAD_FAIL' "$out/boot.log"

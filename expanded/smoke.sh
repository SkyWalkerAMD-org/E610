#!/bin/bash
set -Eeuo pipefail
work=$(realpath "${1:?work}")
out=$(realpath "${2:?output}")
kernel=${3:?kernel}
kind=${4:?kind}
root=$work/smoke-root
mkdir -p "$root"/{bin,dev,proc,sys,modules}
cp /usr/bin/busybox "$root/bin/busybox"
for c in sh mount insmod rmmod uname dmesg poweroff cat grep sleep; do ln -sf busybox "$root/bin/$c"; done
echo "$kernel" > "$root/expected-kernel"
echo "$kind" > "$root/kind"
: > "$root/load-order.txt"
while read -r action file rest; do
  [[ $action == insmod ]] || continue
  name=${file##*/}
  case "$name" in
    *.zst) zstd -dc "$file" > "$root/modules/${name%.zst}"; name=${name%.zst} ;;
    *.xz) xz -dc "$file" > "$root/modules/${name%.xz}"; name=${name%.xz} ;;
    *) cp "$file" "$root/modules/$name" ;;
  esac
  echo "$name" >> "$root/load-order.txt"
done < "$out/load-order.txt"
cp "$(dirname "$0")/smoke-init.sh" "$root/init"
chmod 755 "$root/init"
mknod "$root/dev/console" c 5 1
mknod "$root/dev/null" c 1 3
(cd "$root" && find . -print0 | cpio --null -o --format=newc --owner=0:0) | gzip -1 > "$work/smoke-initrd.gz"
vmlinuz=$work/root/boot/vmlinuz-$kernel
[[ -f $vmlinuz ]] || vmlinuz=$work/root/lib/modules/$kernel/vmlinuz
timeout 240 qemu-system-x86_64 -machine pc,accel=tcg -cpu max -smp 2 -m 1024 \
  -kernel "$vmlinuz" -initrd "$work/smoke-initrd.gz" -append 'console=ttyS0 rdinit=/init panic=1' \
  -display none -serial stdio -monitor none -nic none -no-reboot 2>&1 | tee "$out/boot.log"
grep -q "^E610_KERNEL_LOAD_PASS kernel=$kernel kind=$kind" "$out/boot.log"
if grep -q E610_SMOKE_FAIL "$out/boot.log"; then exit 1; fi

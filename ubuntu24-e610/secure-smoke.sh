#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail
export LC_ALL=C
work=$(realpath "${1:?work}")
out=$(realpath "${2:?output}")
here=$(cd "$(dirname "$0")" && pwd)
kernel=6.8.0-31-generic
root=$work/smoke-root
esp=$work/esp
mkdir -p "$root"/{bin,dev,proc,sys,modules} "$esp/EFI/BOOT" "$esp/boot/grub"
cp /usr/bin/busybox "$root/bin/busybox"
for cmd in sh mount insmod rmmod uname dmesg poweroff cat grep od tr sleep; do ln -sf busybox "$root/bin/$cmd"; done
cp "$here/smoke-init.sh" "$root/init"
chmod 755 "$root/init"
cp "$work/unsigned-ixgbe.ko" "$root/unsigned-ixgbe.ko"
: > "$root/load-order.txt"
while read -r action file rest; do
  [[ $action == insmod ]] || continue
  filename=${file##*/}
  case "$filename" in
    *.zst) zstd -dc "$file" > "$root/modules/${filename%.zst}"; filename=${filename%.zst} ;;
    *.xz) xz -dc "$file" > "$root/modules/${filename%.xz}"; filename=${filename%.xz} ;;
    *) cp "$file" "$root/modules/$filename" ;;
  esac
  echo "$filename" >> "$root/load-order.txt"
done < "$out/load-order.txt"
mknod "$root/dev/console" c 5 1
mknod "$root/dev/null" c 1 3
(cd "$root" && find . -print0 | cpio --null -o --format=newc --owner=0:0) | gzip -1 > "$work/smoke-initrd.gz"
cp "$work/kernel/boot/vmlinuz-$kernel" "$esp/vmlinuz"
cp "$work/smoke-initrd.gz" "$esp/initrd.gz"
cp /usr/lib/shim/shimx64.efi.signed.latest "$esp/EFI/BOOT/BOOTX64.EFI"
cp /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed "$esp/EFI/BOOT/grubx64.efi"
cp /usr/lib/shim/mmx64.efi "$esp/EFI/BOOT/mmx64.efi"
cat > "$esp/EFI/BOOT/grub.cfg" <<'EOF'
serial --unit=0 --speed=115200
terminal_input serial
terminal_output serial
set timeout=0
search --file --set=root /vmlinuz
linux /vmlinuz console=ttyS0,115200 rdinit=/init panic=1
initrd /initrd.gz
boot
EOF
cp "$esp/EFI/BOOT/grub.cfg" "$esp/boot/grub/grub.cfg"
mkdir -p "$esp/EFI/ubuntu"
cp "$esp/EFI/BOOT/grub.cfg" "$esp/EFI/ubuntu/grub.cfg"
virt-fw-vars --input /usr/share/OVMF/OVMF_VARS_4M.ms.fd --output "$work/test-vars.fd" \
  --add-mok 8cdd3896-cb26-4798-b3dc-886aaf06384f "$work/release-signing.pem" --secure-boot
set +e
timeout 240 qemu-system-x86_64 -machine q35,smm=on,accel=tcg -cpu max -smp 2 -m 1024 \
  -global driver=cfi.pflash01,property=secure,value=on \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.ms.fd \
  -drive if=pflash,format=raw,unit=1,file="$work/test-vars.fd" \
  -drive if=virtio,format=raw,file=fat:rw:"$esp" \
  -display none -serial stdio -monitor none -nic none -no-reboot 2>&1 | tee "$out/secure-boot.log"
rc=${PIPESTATUS[0]}
set -e
test "$rc" = 0
grep -q '^E610_SECURE_BOOT_LOAD_PASS kernel=6.8.0-31-generic' "$out/secure-boot.log"
! grep -q 'E610_SMOKE_FAIL' "$out/secure-boot.log"

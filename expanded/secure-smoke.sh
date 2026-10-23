#!/bin/bash
set -Eeuo pipefail
export LC_ALL=C
work=$(realpath "${1:?work}")
out=$(realpath "${2:?output}")
kernel=${3:?kernel}
system=${4:?system}
root=$work/secure-root
esp=$work/esp
cp -a "$work/smoke-root" "$root"
mkdir -p "$esp/EFI/BOOT" "$esp/EFI/ubuntu" "$esp/boot/grub"
for c in od tr; do ln -sf busybox "$root/bin/$c"; done
cp -a "$work/mok-tools/." "$root/"
ln -sf /usr/bin/mokutil "$root/bin/mokutil"
cp "$out/E610-MOK.der" "$root/"
cp "$(dirname "$0")/mok-status.sh" "$root/"
openssl req -new -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=Untrusted test/' -keyout /dev/null -outform DER -out "$root/untrusted.der" 2>/dev/null
cp "$work/unsigned-ixgbe.ko" "$root/unsigned-ixgbe.ko"
sed "s/5.15.0-78-generic/$kernel/g" "$(dirname "$0")/../ubuntu22-offline/smoke-init.sh" > "$root/init"
chmod 755 "$root/init"
(cd "$root" && find . -print0 | cpio --null -o --format=newc --owner=0:0) | gzip -1 > "$esp/initrd.gz"
vmlinuz=$work/root/boot/vmlinuz-$kernel
[[ -f $vmlinuz ]] || vmlinuz=$work/root/lib/modules/$kernel/vmlinuz
cp "$vmlinuz" "$esp/vmlinuz"
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
cp "$esp/EFI/BOOT/grub.cfg" "$esp/EFI/ubuntu/grub.cfg"
cp "$esp/EFI/BOOT/grub.cfg" "$esp/boot/grub/grub.cfg"
extra=()
if [[ $system == rocky ]]; then
    # Ubuntu's shim is used only by this test harness. Add the Rocky kernel's
    # existing vendor certificate; no kernel is changed or re-signed.
    sbattach --detach "$work/kernel-signature.p7" "$esp/vmlinuz"
    openssl pkcs7 -inform DER -in "$work/kernel-signature.p7" -print_certs -out "$work/kernel-certificates.pem"
    openssl x509 -in "$work/kernel-certificates.pem" -out "$work/kernel-signing.pem"
    extra=(--add-mok e7307d90-5e9f-4a0b-9807-4c6beb79af52 "$work/kernel-signing.pem")
fi
virt-fw-vars --input /usr/share/OVMF/OVMF_VARS_4M.ms.fd --output "$work/secure-vars.fd" \
  --add-mok 8cdd3896-cb26-4798-b3dc-886aaf06384f "$work/release-signing.pem" "${extra[@]}" --secure-boot
timeout 240 qemu-system-x86_64 -machine q35,smm=on,accel=tcg -cpu max -smp 2 -m 1024 \
  -global driver=cfi.pflash01,property=secure,value=on \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.ms.fd \
  -drive if=pflash,format=raw,unit=1,file="$work/secure-vars.fd" \
  -drive if=virtio,format=raw,file=fat:rw:"$esp" \
  -display none -serial stdio -monitor none -nic none -no-reboot 2>&1 | tee "$out/secure-boot.log"
grep -q "^E610_SECURE_BOOT_LOAD_PASS kernel=$kernel" "$out/secure-boot.log"
if grep -q E610_SMOKE_FAIL "$out/secure-boot.log"; then exit 1; fi

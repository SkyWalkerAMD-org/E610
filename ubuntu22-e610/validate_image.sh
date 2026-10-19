#!/bin/bash
# Exercise the actual ISO and Ubuntu initramfs-tools without using host modules.
set -Eeuo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
[ "$(id -u)" = 0 ] || { echo 'Run as root in an isolated build host' >&2; exit 1; }
[ "$#" = 3 ] || { echo 'Usage: validate_image.sh ORIGINAL_ISO ADAPTED_ISO NEW_WORK_DIR' >&2; exit 2; }
original=$(realpath "$1")
adapted=$(realpath "$2")
work=$(realpath -m "$3")
script_dir=$(cd "$(dirname "$0")" && pwd)
[ ! -e "$work" ] || { echo 'Work directory must not exist' >&2; exit 1; }
umask 022
mkdir -p "$work"/{original,media,root,upper,overlay-work}
mounts=()
cleanup() { for ((i=${#mounts[@]}-1;i>=0;i--)); do umount "${mounts[$i]}"; done; }
trap cleanup EXIT
mount -o loop,ro "$original" "$work/original"
mounts+=("$work/original")
mount -o loop,ro "$adapted" "$work/media"
mounts+=("$work/media")
(cd "$work/media" && md5sum -c --quiet md5sum.txt)
cmp "$work/original/casper/vmlinuz" "$work/media/casper/vmlinuz"
python3 - "$script_dir" "$work" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from build_iso import main_offset
root=Path(sys.argv[2])
a=(root/'original/casper/initrd').read_bytes()
b=(root/'media/casper/initrd').read_bytes()
assert a[:main_offset(a)] == b[:main_offset(b)], 'Early CPU microcode archives changed'
print('PASS: all media checksums, unchanged kernel and early microcode')
PY
stem=ubuntu-server-minimal
for spec in "base:$stem" "server:$stem.ubuntu-server" "installer:$stem.ubuntu-server.installer" "generic:$stem.ubuntu-server.installer.generic"; do
    name=${spec%%:*}; image=${spec#*:}
    unsquashfs -no-progress -processors 4 -d "$work/$name" "$work/media/casper/$image.squashfs" > "$work/extract-$name.log" 2>&1
done
mount -t overlay overlay -o "lowerdir=$work/generic:$work/installer:$work/server:$work/base,upperdir=$work/upper,workdir=$work/overlay-work" "$work/root"
mounts+=("$work/root")
mount -t proc -o ro proc "$work/root/proc"
mounts+=("$work/root/proc")
mount --bind /dev "$work/root/dev"
mounts+=("$work/root/dev")
chroot "$work/root" depmod 5.15.0-78-generic
chroot "$work/root" update-initramfs -c -k 5.15.0-78-generic > "$work/initramfs.log" 2>&1
chroot "$work/root" /usr/local/sbin/ventoy-e610-verify
chroot "$work/root" unmkinitramfs /boot/initrd.img-5.15.0-78-generic /tmp/e610-initramfs-check
expected=$(cat "$work/root/usr/share/ventoy-e610/module.sha256")
mapfile -t modules < <(find "$work/root/tmp/e610-initramfs-check" -name ixgbe.ko -type f)
[ "${#modules[@]}" -ge 1 ]
for module in "${modules[@]}"; do printf '%s  %s\n' "$expected" "$module" | sha256sum -c -; done
chroot "$work/root" /usr/local/sbin/ventoy-center-update-policy --apply --offline > "$work/policy.log" 2>&1
chroot "$work/root" /usr/local/sbin/ventoy-center-update-policy --check
printf 'E610_UBUNTU_IMAGE_VALIDATION_PASS\n'

#!/bin/sh
# Driver-only installer completion hook. Never changes partitions or accounts.
set -eu
export LC_ALL=C
src=${0%/*}
src=$(CDPATH= cd -- "$src" && pwd)
target=${1:?Missing installed root}
[ -d "$target" ] && [ "$target" != / ] && [ -f "$target/etc/os-release" ] || exit 1
target=$(readlink -f "$target")
[ "$target" != / ] || exit 1
for p in "$target/var" "$target/var/lib" "$target/var/lib/ventoy-e610" "$target/usr/local" "$target/usr/local/sbin"; do
    [ ! -L "$p" ] || { echo "E610: unsafe target directory $p" >&2; exit 1; }
done
mkdir -p "$target/var/lib/ventoy-e610" "$target/usr/local/sbin"
status=$target/var/lib/ventoy-e610/installation.tsv
[ ! -L "$status" ] || exit 1
tmp=$(mktemp "$target/var/lib/ventoy-e610/.install.XXXXXX")
trap 'rm -f "$tmp"' EXIT HUP INT TERM
count=0
for boot in "$target"/boot/vmlinuz-*; do
    [ -f "$boot" ] || continue
    k=${boot##*/vmlinuz-}
    case "$k" in 0-rescue-*) continue;; esac
    case "$k" in *[!a-zA-Z0-9._+-]*|'') exit 1;; esac
    count=$((count+1))
    native=1
    aliases=$(chroot "$target" modinfo -k "$k" -F alias ixgbe 2>/dev/null) || native=0
    for id in 57AE 57AF 57B0 57B1 57B2; do
        printf '%s\n' "$aliases" | grep -q "v00008086d0000$id" || native=0
    done
    module=$src/drivers/$k/ixgbe.ko
    if [ ! -f "$module" ]; then
        if [ "$native" = 1 ]; then
            printf '%s\tnative\t-\n' "$k" >> "$tmp"
            continue
        fi
        echo "E610: no validated driver for installed kernel $k; installation cannot be accepted" >&2
        exit 1
    fi
    # Manifest is generated only after this exact module passed kernel loading.
    (cd "$src/drivers/$k"; sha256sum -c SHA256SUMS)
    [ "$(modinfo -F vermagic "$module" | cut -d ' ' -f 1)" = "$k" ]
    dir=$target/lib/modules/$k
    resolved=$(readlink -f "$dir")
    case "$resolved" in "$target"/*) ;; *) echo 'E610: modules path escapes installed root' >&2; exit 1;; esac
    [ -d "$resolved" ] && [ ! -L "$resolved/updates" ] && [ ! -L "$resolved/updates/e610" ] || exit 1
    mkdir -p "$resolved/updates/e610"
    dest=$resolved/updates/e610/ixgbe.ko
    [ ! -L "$dest" ] || exit 1
    if [ -f "$dest" ] && ! cmp -s "$module" "$dest"; then
        # Preserve an existing custom module; no silent replacement on reinstall.
        echo "E610: a different custom module already exists for $k" >&2; exit 1
    fi
    cp "$module" "$dest"
    chmod 0644 "$dest"
    if [ -x "$target/sbin/restorecon" ] || [ -x "$target/usr/sbin/restorecon" ]; then
        chroot "$target" restorecon -R "/lib/modules/$k/updates/e610"
    fi
    chroot "$target" depmod -a "$k"
    selected=$(chroot "$target" modinfo -k "$k" -F filename ixgbe)
    case "$selected" in */updates/e610/ixgbe.ko) ;; *) echo 'E610: driver precedence check failed' >&2; exit 1;; esac
    if [ -x "$target/usr/sbin/update-initramfs" ]; then
        # A hostonly image built on a different NIC must still carry E610.
        list=$target/etc/initramfs-tools/modules
        [ ! -L "$list" ] || exit 1
        if ! grep -Eq '^[[:space:]]*ixgbe([[:space:]]|$)' "$list" 2>/dev/null; then
            printf '\n# E610 installer persistence\nixgbe\n' >> "$list"
        fi
        chroot "$target" update-initramfs -u -k "$k"
    elif [ -x "$target/usr/bin/dracut" ]; then
        chroot "$target" dracut --force --add-drivers ixgbe "/boot/initramfs-$k.img" "$k"
    else
        echo 'E610: unsupported initramfs builder' >&2; exit 1
    fi
    hash=$(sha256sum "$module" | cut -d ' ' -f 1)
    printf '%s\tinjected\t%s\n' "$k" "$hash" >> "$tmp"
    if [ -f "$src/drivers/$k/E610-MOK.der" ]; then
        cp "$src/drivers/$k/E610-MOK.der" "$target/var/lib/ventoy-e610/$k-MOK.der"
    fi
done
[ "$count" -gt 0 ] || { echo 'E610: no installed kernel found' >&2; exit 1; }
mv "$tmp" "$status"
chmod 0644 "$status"
# EL rescue filenames contain a machine ID, not a kernel ABI. Match the copied
# kernel image to an installed release, then rebuild its separate rescue initrd.
rescue_status=$target/var/lib/ventoy-e610/rescue.tsv
[ ! -L "$rescue_status" ] || exit 1
: > "$rescue_status"
for rescue in "$target"/boot/vmlinuz-0-rescue-*; do
    [ -f "$rescue" ] || continue
    release=''
    for boot in "$target"/boot/vmlinuz-*; do
        k=${boot##*/vmlinuz-}
        case "$k" in 0-rescue-*) continue;; esac
        if cmp -s "$rescue" "$boot"; then release=$k; break; fi
    done
    [ -n "$release" ] || { echo 'E610: rescue kernel has no matching installed ABI' >&2; exit 1; }
    name=${rescue##*/vmlinuz-}
    case "$name" in *[!a-zA-Z0-9._+-]*) exit 1;; esac
    chroot "$target" dracut --force --no-hostonly --add-drivers ixgbe "/boot/initramfs-$name.img" "$release"
    printf '%s\t%s\n' "$name" "$release" >> "$rescue_status"
done
chmod 0644 "$rescue_status"
cp "$src/verify.sh" "$target/usr/local/sbin/ventoy-e610-verify"
chmod 0755 "$target/usr/local/sbin/ventoy-e610-verify"
chroot "$target" /bin/sh /usr/local/sbin/ventoy-e610-verify --offline
echo 'E610 exact-kernel driver and installed initramfs verified. Physical E610 networking still requires a card.'

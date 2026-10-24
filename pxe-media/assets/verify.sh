#!/bin/sh
set -eu
export LC_ALL=C
status=/var/lib/ventoy-e610/installation.tsv
[ -s "$status" ] || { echo 'E610 installation manifest missing' >&2; exit 1; }
listing=$(mktemp)
trap 'rm -f "$listing"' EXIT HUP INT TERM
list_initrd() {
    # Do not pipe to grep -q: closing its input early makes zstd/lsinitramfs
    # fail with SIGPIPE and can hide a genuine decompression error.
    if command -v lsinitramfs >/dev/null; then lsinitramfs "$1" > "$listing"
    else lsinitrd "$1" > "$listing"; fi
}
tab=$(printf '\t')
while IFS="$tab" read -r k kind expected; do
    case "$k" in ''|*[!a-zA-Z0-9._+-]*) exit 1;; esac
    file=$(modinfo -k "$k" -F filename ixgbe)
    [ "$(modinfo -k "$k" -F vermagic ixgbe | cut -d ' ' -f 1)" = "$k" ]
    aliases=$(modinfo -k "$k" -F alias ixgbe)
    for id in 57AE 57AF 57B0 57B1 57B2; do
        printf '%s\n' "$aliases" | grep -q "v00008086d0000$id"
    done
    if [ "$kind" = injected ]; then
        case "$file" in */updates/e610/ixgbe.ko) ;; *) exit 1;; esac
        [ "$(sha256sum "$file" | cut -d ' ' -f 1)" = "$expected" ]
        if command -v lsinitramfs >/dev/null; then
            list_initrd "/boot/initrd.img-$k"
        else
            list_initrd "/boot/initramfs-$k.img"
        fi
        grep -Fq "lib/modules/$k/updates/e610/ixgbe.ko" "$listing"
    fi
    echo "E610_VERIFY_PASS kernel=$k kind=$kind"
done < "$status"
if [ -f /var/lib/ventoy-e610/rescue.tsv ]; then
    while IFS="$tab" read -r name k; do
        case "$name" in 0-rescue-*) ;; *) exit 1;; esac
        case "$name$k" in *[!a-zA-Z0-9._+-]*) exit 1;; esac
        if grep -Fqx "$k${tab}native${tab}-" "$status"; then
            list_initrd "/boot/initramfs-$name.img"
            grep -Fq 'ixgbe.ko' "$listing"
        else
            list_initrd "/boot/initramfs-$name.img"
            grep -Fq "lib/modules/$k/updates/e610/ixgbe.ko" "$listing"
        fi
        echo "E610_RESCUE_VERIFY_PASS kernel=$k"
    done < /var/lib/ventoy-e610/rescue.tsv
fi
if [ "${1:-}" != --offline ]; then
    echo 'E610 link/DHCP must be verified on physical hardware; this check does not certify link state.'
    if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled'; then
        for cert in /var/lib/ventoy-e610/*-MOK.der; do
            [ ! -f "$cert" ] || mokutil --test-key "$cert"
        done
    fi
fi

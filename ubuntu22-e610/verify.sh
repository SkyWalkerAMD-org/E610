#!/bin/sh
set -eu
export LC_ALL=C
kernel=$(cat /usr/share/ventoy-e610/kernel)
module=/lib/modules/$kernel/updates/ixgbe.ko
printf '%s  %s\n' "$(cat /usr/share/ventoy-e610/module.sha256)" "$module" | sha256sum -c -
[ "$(modinfo -F version "$module")" = 6.4.5 ]
[ "$(modinfo -F vermagic "$module" | cut -d ' ' -f 1)" = "$kernel" ]
[ "$(modinfo -k "$kernel" -n ixgbe)" = "$module" ]
lsinitramfs "/boot/initrd.img-$kernel" | grep -qx "usr$module\|${module#/}"
printf 'E610: driver 6.4.5 and initramfs verified for %s\n' "$kernel"

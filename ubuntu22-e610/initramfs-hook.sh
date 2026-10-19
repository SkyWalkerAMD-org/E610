#!/bin/sh
set -eu
PREREQ=""
case "${1:-}" in prereqs) echo "$PREREQ"; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
expected=$(cat /usr/share/ventoy-e610/kernel)
[ "$version" = "$expected" ] || { echo "E610: kernel $version has no validated driver; expected $expected" >&2; exit 1; }
module=/lib/modules/$version/updates/ixgbe.ko
printf '%s  %s\n' "$(cat /usr/share/ventoy-e610/module.sha256)" "$module" | sha256sum -c -
[ "$(modinfo -F version "$module")" = 6.4.5 ]
manual_add_modules ixgbe
test -f "$DESTDIR$module"

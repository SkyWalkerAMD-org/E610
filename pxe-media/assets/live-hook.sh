#!/bin/sh
set -eu
# The compositor runs the existing iVentoy hook first. Keep its PXE selection
# and manual setup preload behavior, then prepare this independent driver hook.
[ -f /scripts/casper ] || exit 0
grep -q '/ventoy-e610/prepare-live.sh' /init && exit 0
[ "$(grep -c '^[[:space:]]*maybe_break init$' /init)" = 1 ] || exit 1
sed -i '/^[[:space:]]*maybe_break init$/i /ventoy/busybox/sh /ventoy-e610/prepare-live.sh "$rootmnt"' /init

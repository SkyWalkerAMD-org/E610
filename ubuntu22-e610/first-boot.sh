#!/bin/sh
set -eu
case "$(stat -f -c %T /)" in overlay*|aufs|squashfs|tmpfs) exit 0;; esac
[ "$(uname -r)" = "$(cat /usr/share/ventoy-e610/kernel)" ]
/usr/local/sbin/ventoy-e610-verify
/usr/local/sbin/ventoy-center-update-policy --apply
/usr/local/sbin/ventoy-center-update-policy --check
if [ -e /sys/module/ixgbe/version ]; then
    [ "$(cat /sys/module/ixgbe/version)" = 6.4.5 ]
fi
echo 'E610: installed-system verification and kernel/update policy passed'

#!/bin/sh
[ -f /sysroot/etc/os-release ] || return 0
/bin/sh /ventoy-e610/prepare-live.sh /sysroot

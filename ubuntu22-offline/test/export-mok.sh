#!/bin/bash
set -Eeuo pipefail
dpkg-deb -x /mok-debs/mokutil.deb /
cp -L --parents /usr/bin/mokutil /export/
while read -r library; do
    cp -L --parents "$library" /export/
done < <(ldd /usr/bin/mokutil | awk '/=> \// {print $3} /^[[:space:]]*\// {print $1}')
mokutil --version
dpkg-deb -f /mok-debs/mokutil.deb Package Version

#!/bin/bash
set -Eeuo pipefail
cp -L --parents /usr/bin/mokutil /export/
while read -r library; do
    cp -L --parents "$library" /export/
done < <(ldd /usr/bin/mokutil | awk '/=> \// {print $3} /^[[:space:]]*\// {print $1}')
mokutil --version

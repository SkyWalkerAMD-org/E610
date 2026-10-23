#!/bin/bash
# Exact kernel fixtures for disposable CI containers, never installed on the host.
set -Eeuo pipefail
work=$(realpath -m "${1:?work}")
mkdir -p "$work/ubuntu22" "$work/ubuntu24"
iso=$work/ubuntu-22.04.3-live-server-amd64.iso
curl --fail --location --retry 3 -o "$iso" https://old-releases.ubuntu.com/releases/22.04.3/ubuntu-22.04.3-live-server-amd64.iso
echo "a4acfda10b18da50e2ec50ccaf860d7f20b389df8765611142305c0e911d16fd  $iso" | sha256sum -c -
xorriso -osirrox on -indev "$iso" \
    -extract /pool/main/l/linux-signed/linux-image-5.15.0-78-generic_5.15.0-78.85_amd64.deb "$work/ubuntu22/linux-image.deb" \
    -extract /pool/main/l/linux/linux-modules-5.15.0-78-generic_5.15.0-78.85_amd64.deb "$work/ubuntu22/linux-modules.deb" \
    -extract /pool/main/l/linux/linux-modules-extra-5.15.0-78-generic_5.15.0-78.85_amd64.deb "$work/ubuntu22/linux-modules-extra.deb"
(cd "$work/ubuntu24" && apt-get download linux-image-6.8.0-31-generic=6.8.0-31.31 linux-modules-6.8.0-31-generic=6.8.0-31.31)
(cd "$work" && sha256sum ubuntu22/*.deb ubuntu24/*.deb > kernel-fixtures.sha256)

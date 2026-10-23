#!/bin/bash
# Use the official Ubuntu archives for this ephemeral build VM, avoiding
# unrelated preinstalled third-party repositories during apt update.
set -Eeuo pipefail
sources=${RUNNER_TEMP:?}/e610-build-sources.list
cat > "$sources" <<'EOF'
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://archive.ubuntu.com/ubuntu noble main universe
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://archive.ubuntu.com/ubuntu noble-updates main universe
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://security.ubuntu.com/ubuntu noble-security main universe
EOF
options=(-o "Dir::Etc::sourcelist=$sources" -o 'Dir::Etc::sourceparts=-' -o Acquire::ForceIPv4=true -o Acquire::Retries=2 -o Acquire::http::Timeout=30)
timeout 300 sudo apt-get "${options[@]}" update -qq
packages=(xorriso squashfs-tools)
if [[ ${1:-} != media ]]; then
    packages+=(gcc-11 gcc-12 gcc-13 build-essential libelf-dev libssl-dev kmod curl openssl qemu-system-x86 busybox-static cpio zstd ovmf python3-virt-firmware shim-signed grub-efi-amd64-signed mokutil sbsigntool)
fi
timeout 600 sudo apt-get "${options[@]}" install -y --no-install-recommends "${packages[@]}"

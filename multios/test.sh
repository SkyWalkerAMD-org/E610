#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
trap 'rc=$?; echo "TEST_FAIL line=$LINENO command=$BASH_COMMAND exit=$rc" >&2; exit "$rc"' ERR
: "${KVER:?}" "${TARGET:?}"
[[ -f /.dockerenv && $EUID == 0 ]]
if command -v make >/dev/null || command -v gcc >/dev/null; then
    echo 'Test image must not contain a compiler or make.' >&2; exit 1
fi
cache=/opt/e610-offline/multios-6.4.5-r1
runfile=/media/E610-MultiOS-6.4.5-r1.run
case "$TARGET" in
    centos7)
        selected_cache=/opt/e610-offline/centos7.9-r2
        dest=/lib/modules/$KVER/updates/drivers/net/ethernet/intel/ixgbe/ixgbe.ko
        state=/var/lib/e610-ixgbe/$KVER
        image=/boot/initramfs-$KVER.img
        backup_image=initramfs
        printf 'hostonly="no"\n' > /etc/dracut.conf.d/e610-multios-test.conf
        dracut --force --no-hostonly --kver "$KVER" --add-drivers ixgbe "$image" ;;
    ubuntu22|ubuntu24)
        if [[ $TARGET == ubuntu22 ]]; then
            selected_cache=/opt/e610-offline/ubuntu22-5.15.0-78-r1
        else selected_cache=/opt/e610-offline/ubuntu24-6.8.0-31-r1; fi
        dest=/lib/modules/$KVER/updates/e610/ixgbe.ko
        state=/var/lib/e610-ixgbe/$TARGET-$KVER
        image=/boot/initrd.img-$KVER
        backup_image=initrd
        for deb in /kernel-debs/*.deb; do
            dpkg-deb --fsys-tarfile "$deb" | tar -C / --keep-directory-symlink -xf -
        done
        depmod -a "$KVER"
        update-initramfs -c -k "$KVER" ;;
    *) exit 2 ;;
esac
baseline=$(sha256sum "$image" | awk '{print $1}')
(cd /media && sha256sum -c SHA256SUMS)
runuser -u nobody -- bash "$runfile" --list
test ! -e "$cache"
cp "$runfile" /tmp/corrupt.run
printf corrupt >> /tmp/corrupt.run
if bash /tmp/corrupt.run --kernel "$KVER"; then exit 1; fi
test ! -e "$cache"
test ! -e "$dest"
# Unsupported kernel, unsupported OS, and a kernel from another supported OS
# must all be rejected before selecting or unpacking any OS-specific installer.
if bash /media/install.sh --kernel unvalidated-kernel; then exit 1; fi
test ! -e "$selected_cache"
cp -L /etc/os-release /tmp/original-os-release
printf 'ID=rocky\nVERSION_ID=9\n' > /etc/os-release
if bash /media/install.sh --kernel "$KVER"; then exit 1; fi
cp /tmp/original-os-release /etc/os-release
if [[ $TARGET == ubuntu24 ]]; then wrong_kernel=5.15.0-78-generic; else wrong_kernel=6.8.0-31-generic; fi
if bash /media/install.sh --kernel "$wrong_kernel"; then exit 1; fi
test ! -e "$selected_cache"
test ! -e "$dest"
echo E610_MULTIOS_REJECTION_PASS
# Direct tar.gz entry point preflight, using the same selector as the .run.
mkdir /tmp/direct-package
tar -xzf /release/E610-MultiOS-6.4.5-r1.tar.gz -C /tmp/direct-package
direct=/tmp/direct-package/E610-MultiOS-6.4.5-r1
bash "$direct/install.sh" --kernel "$KVER" --check | tee /tmp/selection.log
grep -q "^E610_MULTIOS_SELECTED=$TARGET kernel=$KVER$" /tmp/selection.log
test ! -e "$dest"
case "$TARGET" in
    centos7) module=$selected_cache/ixgbe-6.4.5-$KVER/ixgbe.ko ;;
    *) module=$selected_cache/ixgbe.ko ;;
esac
expected=$(sha256sum "$module" | awk '{print $1}')
for other in /opt/e610-offline/centos7.9-r2 /opt/e610-offline/ubuntu22-5.15.0-78-r1 /opt/e610-offline/ubuntu24-6.8.0-31-r1; do
    [[ $other == "$selected_cache" ]] || test ! -e "$other"
done
# First install with the original standalone installer, then exercise switching
# to the unified ISO. This must preserve the first backup and the installed image.
standalone=$(find "$direct/payloads" -maxdepth 1 -type f -name '*.run' | while read -r file; do
    case "$TARGET:$file" in
        centos7:*CentOS7.9*|ubuntu22:*Ubuntu22.04.3*|ubuntu24:*Ubuntu24.04*) echo "$file" ;;
    esac
done)
[[ -n $standalone && $standalone != *$'\n'* ]]
bash "$standalone" --kernel "$KVER"
backup=$(readlink -f "$state/latest")
installed_image=$(sha256sum "$image" | awk '{print $1}')
bash /media/install.sh --kernel "$KVER" | tee /tmp/selection.log
grep -q "^E610_MULTIOS_SELECTED=$TARGET kernel=$KVER$" /tmp/selection.log
test "$(readlink -f "$state/latest")" = "$backup"
test "$(sha256sum "$image" | awk '{print $1}')" = "$installed_image"
test "$(sha256sum "$backup/$backup_image" | awk '{print $1}')" = "$baseline"
test "$(sha256sum "$dest" | awk '{print $1}')" = "$expected"
test "$(readlink -f "$(modinfo -k "$KVER" -n ixgbe)")" = "$(readlink -f "$dest")"
echo E610_MULTIOS_EXISTING_INSTALL_PRESERVED
# Recovery using only the persisted common entry point, then a fresh ISO install.
(cd /tmp && bash "$cache/install.sh" --kernel "$KVER" --rollback)
test ! -e "$dest"
test "$(sha256sum "$image" | awk '{print $1}')" = "$baseline"
bash /media/install.sh --kernel "$KVER"
test "$(sha256sum "$dest" | awk '{print $1}')" = "$expected"
if [[ $TARGET == centos7 ]]; then
    embedded=$(lsinitrd "$image" | awk '$NF ~ /updates\/drivers\/net\/ethernet\/intel\/ixgbe\/ixgbe.ko$/ {print $NF}')
    [[ -n $embedded && $embedded != *$'\n'* ]]
    lsinitrd -f "$embedded" "$image" > /tmp/embedded-ixgbe.ko
    for field in version vermagic srcversion; do
        test "$(modinfo -F "$field" /tmp/embedded-ixgbe.ko)" = "$(modinfo -F "$field" "$module")"
    done
else
    mkdir /tmp/embedded-initrd
    unmkinitramfs "$image" /tmp/embedded-initrd
    mapfile -t embedded < <(find /tmp/embedded-initrd -type f -path '*/updates/e610/ixgbe.ko')
    [[ ${#embedded[@]} == 1 ]]
    test "$(sha256sum "${embedded[0]}" | awk '{print $1}')" = "$expected"
    test -n "$(modinfo -F signer "$dest")"
fi
backup=$(readlink -f "$state/latest")
(cd /tmp && bash "$runfile" --kernel "$KVER")
test "$(readlink -f "$state/latest")" = "$backup"
# Corrupted common cache must not be silently overwritten or executed.
cp "$cache/install.sh" /tmp/good-dispatcher
printf '\n# altered\n' >> "$cache/install.sh"
if bash "$runfile" --kernel "$KVER"; then exit 1; fi
cp /tmp/good-dispatcher "$cache/install.sh"
(cd /tmp && bash "$cache/install.sh" --kernel "$KVER" --rollback)
test ! -e "$dest"
test "$(sha256sum "$image" | awk '{print $1}')" = "$baseline"
test -z "$(find /opt/e610-offline -maxdepth 1 -name '.stage.*' -print -quit)"
printf 'E610_MULTIOS_TEST_PASS target=%s kernel=%s\n' "$TARGET" "$KVER"

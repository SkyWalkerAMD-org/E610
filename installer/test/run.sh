#!/bin/bash
set -Eeuo pipefail
export LC_ALL=C
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
trap 'rc=$?; echo "TEST_FAIL line=$LINENO command=$BASH_COMMAND exit=$rc" >&2; exit "$rc"' ERR
: "${KVER:?KVER is required}"
[[ -f /.dockerenv && $EUID == 0 ]] || { echo 'Run only in the disposable test container.' >&2; exit 1; }

printf '%s\n' '750e02886c280fc6ce3586bbd1abfd254a3906f66faa470964a7a4328e0e91ac  /fixture.tar.gz' | sha256sum -c -
mkdir /test
tar -xzf /fixture.tar.gz -C /test
cd /test/E610-CentOS7.9-adaptation
cp /input/installer/*.sh .
bash -n install.sh
bash -n uninstall.sh
find . -type f ! -path './SHA256SUMS' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
printf 'hostonly="no"\n' > /etc/dracut.conf.d/e610-installer-test.conf
initrd=/boot/initramfs-$KVER.img
dest=/lib/modules/$KVER/updates/drivers/net/ethernet/intel/ixgbe/ixgbe.ko
state=/var/lib/e610-ixgbe/$KVER
module=$PWD/ixgbe-6.4.5-$KVER/ixgbe.ko
dracut --force --no-hostonly --kver "$KVER" --add-drivers ixgbe "$initrd"
original_path=$(modinfo -k "$KVER" -n ixgbe)
baseline=$(sha256sum "$initrd" | awk '{print $1}')
original_module=$(sha256sum "$original_path" | awk '{print $1}')
expected_module=$(sha256sum "$module" | awk '{print $1}')

expect_failure() {
    local label=$1
    shift
    if "$@"; then echo "UNEXPECTED_SUCCESS $label" >&2; exit 1; fi
    echo "EXPECTED_FAILURE $label"
}
assert_baseline() {
    [[ $(sha256sum "$initrd" | awk '{print $1}') == "$baseline" ]]
    [[ ! -e $dest ]]
    [[ $(modinfo -k "$KVER" -n ixgbe) == "$original_path" ]]
    [[ $(sha256sum "$original_path" | awk '{print $1}') == "$original_module" ]]
}

bash install.sh --check --kernel "$KVER"
[[ ! -d $state ]]
assert_baseline
expect_failure unsupported-kernel bash install.sh --kernel 3.10.0-unvalidated.el7.x86_64
[[ ! -d $state ]]
cp -a "$module" /tmp/saved-module
printf 'corrupted\n' >> "$module"
expect_failure corrupt-payload bash install.sh --kernel "$KVER"
cp -a /tmp/saved-module "$module"
[[ ! -d $state ]]
assert_baseline

bash install.sh --kernel "$KVER"
[[ $(sha256sum "$dest" | awk '{print $1}') == "$expected_module" ]]
[[ $(readlink -f "$(modinfo -k "$KVER" -n ixgbe)") == $(readlink -f "$dest") ]]
relative_module=$(lsinitrd "$initrd" | awk '$NF ~ /updates\/drivers\/net\/ethernet\/intel\/ixgbe\/ixgbe.ko$/ {print $NF}')
[[ -n $relative_module && $relative_module != *$'\n'* ]]
echo "Embedded module path: $relative_module"
lsinitrd -f "$relative_module" "$initrd" > /tmp/initramfs-ixgbe.ko
sha256sum "$module" /tmp/initramfs-ixgbe.ko
# dracut may strip debug sections, so compare module identity rather than
# requiring the extracted ELF to retain the original debug information.
modinfo /tmp/initramfs-ixgbe.ko
for field in version vermagic srcversion; do
    [[ $(modinfo -F "$field" /tmp/initramfs-ixgbe.ko) == $(modinfo -F "$field" "$module") ]]
done
[[ -n $(modinfo -F srcversion /tmp/initramfs-ixgbe.ko) ]]
installed_initrd=$(sha256sum "$initrd" | awk '{print $1}')
first_backup=$(readlink "$state/latest")
backup_count=$(find "$state" -maxdepth 1 -type d -name 'backup.*' | wc -l)
bash install.sh --kernel "$KVER"
[[ $(readlink "$state/latest") == "$first_backup" ]]
[[ $(find "$state" -maxdepth 1 -type d -name 'backup.*' | wc -l) == "$backup_count" ]]
[[ $(sha256sum "$initrd" | awk '{print $1}') == "$installed_initrd" ]]

# A corrupt recovery image must be rejected before deleting the installed module.
cp -a "$state/latest/initramfs" /tmp/saved-backup-initramfs
printf 'corrupted\n' >> "$state/latest/initramfs"
expect_failure corrupt-backup bash uninstall.sh --kernel "$KVER"
[[ $(sha256sum "$dest" | awk '{print $1}') == "$expected_module" ]]
[[ $(sha256sum "$initrd" | awk '{print $1}') == "$installed_initrd" ]]
cp -a /tmp/saved-backup-initramfs "$state/latest/initramfs"
bash uninstall.sh --kernel "$KVER"
assert_baseline
bash uninstall.sh --kernel "$KVER"
assert_baseline

# Test replacing and restoring an already present updates/ixgbe.ko.
case "$original_path" in
    *.xz) xz -dc "$original_path" > "$dest" ;;
    *.gz) gzip -dc "$original_path" > "$dest" ;;
    *) install -D -m 0644 "$original_path" "$dest" ;;
esac
depmod -a "$KVER"
previous_update=$(sha256sum "$dest" | awk '{print $1}')
bash install.sh --kernel "$KVER"
bash uninstall.sh --kernel "$KVER"
[[ $(sha256sum "$dest" | awk '{print $1}') == "$previous_update" ]]
[[ $(sha256sum "$initrd" | awk '{print $1}') == "$baseline" ]]

# Fail after writing a partial temporary initramfs. The old image and module
# must survive, and depmod must resolve the original update module again.
dracut_bin=$(command -v dracut)
mv "$dracut_bin" "$dracut_bin.e610-real"
cat > "$dracut_bin" <<'FAIL_DRACUT'
#!/bin/bash
printf 'partial initramfs\n' > "${!#}"
exit 42
FAIL_DRACUT
chmod 755 "$dracut_bin"
expect_failure dracut-interruption bash install.sh --kernel "$KVER"
mv -f "$dracut_bin.e610-real" "$dracut_bin"
[[ $(sha256sum "$dest" | awk '{print $1}') == "$previous_update" ]]
[[ $(sha256sum "$initrd" | awk '{print $1}') == "$baseline" ]]
[[ $(cat "$state/latest/status") == rolled-back ]]
[[ $(readlink -f "$(modinfo -k "$KVER" -n ixgbe)") == $(readlink -f "$dest") ]]
[[ -z $(find /boot -maxdepth 1 -name '.e610-initramfs-*' -print) ]]

printf 'E610_INSTALLER_TEST_PASS kernel=%s\n' "$KVER"
echo 'Verified preflight, unsupported kernel, corrupt payload, install, embedded module identity, idempotency, corrupt backup, rollback, previous update preservation and dracut failure recovery.'

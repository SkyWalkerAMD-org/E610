#!/bin/sh
set -eu
src=${0%/*}
src=$(CDPATH= cd -- "$src" && pwd)
root=${1:?Missing installer runtime root}
[ "$root" != / ] && [ -f "$root/etc/os-release" ] || exit 1
dest=$root/usr/local/lib/ventoy-e610
mkdir -p "$dest"
cp -a "$src/." "$dest/"
# Permissions are preserved by cp. EL7's early initramfs has no chmod.
if [ -d "$root/usr/share/anaconda/post-scripts" ]; then
    cat > "$root/usr/share/anaconda/post-scripts/98-ventoy-e610.ks" <<'KS'
%post --nochroot --erroronfail --log=/tmp/ventoy-e610-install.log
set -eu
if [ -f /mnt/sysroot/etc/os-release ]; then target=/mnt/sysroot; else target=/mnt/sysimage; fi
/bin/sh /usr/local/lib/ventoy-e610/install-target.sh "$target"
%end
KS
elif [ -x "$root/usr/bin/ubiquity" ]; then
    mkdir -p "$root/usr/lib/ubiquity/target-config"
    cat > "$root/usr/lib/ubiquity/target-config/98ventoy-e610" <<'SH'
#!/bin/sh
set -eu
exec /bin/sh /usr/local/lib/ventoy-e610/install-target.sh "${1:-/target}"
SH
    chmod 0755 "$root/usr/lib/ubiquity/target-config/98ventoy-e610"
else
    mkdir -p "$root/etc/subiquity/postinst.d"
    cat > "$root/etc/subiquity/postinst.d/98-ventoy-e610" <<'SH'
#!/bin/sh
set -eu
exec /bin/sh /usr/local/lib/ventoy-e610/install-target.sh "${TARGET_MOUNT_POINT:-/target}"
SH
    chmod 0755 "$root/etc/subiquity/postinst.d/98-ventoy-e610"
    # Ubuntu 20.04's interactive installer predates postinst.d. Its existing
    # manual-preload adapter runs before LateController signals completion.
    helper=$root/usr/local/lib/ventoy-preload/copy-to-target.sh
    if grep -Eq '^VERSION_ID="?20\.04"?$' "$root/etc/os-release" && [ -f "$helper" ]; then
        if ! grep -q '/ventoy-e610/install-target.sh' "$helper"; then
            printf '\n/bin/sh /usr/local/lib/ventoy-e610/install-target.sh "$target"\n' >> "$helper"
        fi
    fi
fi
echo 'E610 exact-kernel installer completion hook prepared.'

#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Offline installer for the two validated CentOS 7.9 kernels.
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C
umask 077

package_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
mode=install
kver=$(uname -r)
while (($#)); do
    case "$1" in
        --check) mode=check ;;
        --rollback) mode=rollback ;;
        --kernel)
            (($# >= 2)) || { echo '--kernel 需要内核版本。' >&2; exit 2; }
            kver=$2
            shift ;;
        -h|--help)
            echo '用法：sudo bash install.sh [--check | --rollback] [--kernel 内核版本]'
            echo '默认安装当前内核对应的模块；不联网、不卸载当前驱动、不自动重启。'
            exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
    shift
done

die() { echo "错误：$*" >&2; exit 1; }
case "$kver" in
    3.10.0-1160.el7.x86_64|3.10.0-1160.119.1.el7.x86_64) ;;
    *) die "没有适用于 $kver 的预编译模块，请使用匹配的 kernel-devel 从源码构建。" ;;
esac
[[ $(uname -m) == x86_64 ]] || die '仅支持 x86_64。'
grep -q 'CentOS Linux release 7\.9\.2009' /etc/centos-release 2>/dev/null ||
    die '此安装器仅适用于 CentOS Linux 7.9.2009。'
for command in modinfo sha256sum awk cp mv rm mktemp install readlink flock depmod dracut lsinitrd; do
    command -v "$command" >/dev/null || die "缺少命令 $command，请安装 kmod、dracut、util-linux 和 coreutils。"
done
[[ $mode == check || $EUID == 0 ]] || die '请使用 sudo bash install.sh 运行。'

state=/var/lib/e610-ixgbe/$kver
dest=/lib/modules/$kver/updates/drivers/net/ethernet/intel/ixgbe/ixgbe.ko
initrd=/boot/initramfs-$kver.img
module=$package_dir/ixgbe-6.4.5-$kver/ixgbe.ko
backup=
tmp_initrd=
tmp_module=
changed=0

cleanup() {
    [[ -z $tmp_initrd ]] || rm -f -- "$tmp_initrd"
    [[ -z $tmp_module ]] || rm -f -- "$tmp_module"
    return 0
}
trap cleanup EXIT

get_backup() {
    local name
    name=$(readlink -- "$state/latest") || return 1
    [[ $name =~ ^backup\.[[:alnum:]]+$ ]] || die '备份索引无效。'
    backup=$state/$name
    [[ -d $backup && ! -L $backup ]] || die '备份目录不存在或无效。'
}

write_status() {
    printf '%s\n' "$1" > "$backup/status.new" || return 1
    mv -f -- "$backup/status.new" "$backup/status" || return 1
}

restore_backup() {
    local saved_state
    (cd -- "$backup" && sha256sum --status -c backup.sha256) || return 1
    saved_state=$(cat "$backup/module-state") || return 1
    case "$saved_state" in
        present)
            rm -f -- "$dest" || return 1
            cp -a -- "$backup/previous-module" "$dest" || return 1 ;;
        absent) rm -f -- "$dest" || return 1 ;;
        *) return 1 ;;
    esac
    cp -a -- "$backup/initramfs" "$initrd" || return 1
    depmod -a "$kver" || return 1
    write_status rolled-back || return 1
}

failed() {
    local rc=$1
    trap - ERR INT TERM
    ((rc != 0)) || rc=1
    if ((changed)); then
        echo '安装未完成，正在恢复安装前的模块与 initramfs……' >&2
        if restore_backup; then
            echo '已自动恢复；当前运行的驱动未被卸载。' >&2
        else
            echo "自动恢复未完成，请通过控制台保留并检查备份：$backup" >&2
            echo "可重试：sudo bash install.sh --rollback --kernel $kver" >&2
        fi
    fi
    exit "$rc"
}
trap 'failed $?' ERR
trap 'failed 130' INT
trap 'failed 143' TERM

if [[ $mode != check ]]; then
    exec 9>/var/lock/e610-ixgbe.lock
    flock -n 9 || die '已有安装或回退正在运行，请稍后再试。'
fi

if [[ $mode == rollback ]]; then
    get_backup || die "此内核没有安装器创建的备份：$kver"
    if [[ $(cat "$backup/status") == rolled-back ]]; then
        echo '已经回退，无需重复操作。'
        exit 0
    fi
    restore_backup || die "恢复未完成，请保留备份并通过控制台排查：$backup"
    echo "已恢复 $kver 安装前的模块与 initramfs。请在维护窗口手动重启。"
    exit 0
fi

[[ -f $package_dir/SHA256SUMS ]] || die '缺少 SHA256SUMS，请重新解压完整适配包。'
(cd -- "$package_dir" && sha256sum --status -c SHA256SUMS) ||
    die '完整包校验失败，请重新下载并解压，不要修改包内文件。'
[[ -f $module ]] || die "模块缺失：$module"
case "$kver" in
    3.10.0-1160.el7.x86_64) expected=4139a6de9813f4b686e980165e4dfb108f36df015dbe855fbaa014a750aaa341 ;;
    *) expected=db2df6bce892243e338dfa870dfc5119808a97d4cce5ea7f964828847a1e6a3f ;;
esac
[[ $(sha256sum "$module" | awk '{print $1}') == "$expected" ]] || die '模块不是本次已验证的构建产物。'
[[ $(modinfo -F vermagic "$module" | awk '{print $1}') == "$kver" ]] || die '模块 vermagic 与目标内核不匹配。'
[[ -d /lib/modules/$kver ]] || die "目标内核尚未安装：$kver"
[[ -f $initrd && ! -L $initrd ]] || die "未找到常规 initramfs 文件：$initrd"
[[ ! -L $dest ]] || die '安装目标是符号链接，请先按手动部署流程处理现有模块。'
[[ ! -e $dest || -f $dest ]] || die '模块安装目标不是普通文件。'

# These release modules are unsigned. Stop before modifying a system that
# visibly enforces signatures; signing is a separate, machine-specific step.
for flag in /sys/module/module/parameters/sig_enforce; do
    if [[ -r $flag ]] && grep -qiE '^(1|y|yes)$' "$flag"; then
        die '目标机强制模块签名，请按中文说明完成签名后手动安装。'
    fi
done
if grep -qE '(^|[[:space:]])module.sig_enforce=(1|y|Y|true)([[:space:]]|$)' /proc/cmdline; then
    die '内核启动参数启用了模块签名强制检查，请先完成签名。'
fi
for flag in /sys/firmware/efi/efivars/SecureBoot-*; do
    [[ -r $flag ]] || continue
    if [[ $(od -An -j4 -N1 -tu1 "$flag" | tr -d '[:space:]') == 1 ]]; then
        die 'Secure Boot 已启用；本包模块未签名，请按目标机信任链签名后手动安装。'
    fi
done
echo "校验通过：CentOS 7.9 / x86_64 / $kver / ixgbe 6.4.5"
if [[ $mode == check ]]; then
    echo '预检查完成，未修改系统。'
    exit 0
fi

if [[ -e $state/latest || -L $state/latest ]]; then
    get_backup || die '无法读取已有备份记录。'
    case "$(cat "$backup/status")" in
        installed)
            if [[ -f $dest ]] &&
                [[ $(sha256sum "$dest" | awk '{print $1}') == "$expected" ]] &&
                [[ $(readlink -f "$(modinfo -k "$kver" -n ixgbe)") == $(readlink -f "$dest") ]]; then
                echo '该版本已安装；保留原备份，无需重复安装。请在维护窗口手动重启。'
                exit 0
            fi
            die '已有安装记录但系统模块发生变化，请先执行 --rollback 或按手动流程处理。' ;;
        rolled-back) ;;
        *) die '发现未完成的安装，请先运行 sudo bash install.sh --rollback。' ;;
    esac
fi

install -d -m 0700 /var/lib/e610-ixgbe "$state"
backup=$(mktemp -d "$state/backup.XXXXXXXX")
cp -a -- "$initrd" "$backup/initramfs"
if [[ -f $dest ]]; then
    cp -a -- "$dest" "$backup/previous-module"
    printf 'present\n' > "$backup/module-state"
else
    printf 'absent\n' > "$backup/module-state"
fi
(
    cd -- "$backup"
    sha256sum initramfs module-state
    if [[ -f previous-module ]]; then sha256sum previous-module; fi
) > "$backup/backup.sha256"
write_status in-progress
ln -sfn -- "${backup##*/}" "$state/latest.new"
mv -Tf -- "$state/latest.new" "$state/latest"
echo "备份已保存：$backup"
changed=1

install -d -m 0755 "${dest%/*}"
tmp_module=$(mktemp "${dest%/*}/.e610-ixgbe.XXXXXXXX")
install -m 0644 "$module" "$tmp_module"
mv -f -- "$tmp_module" "$dest"
tmp_module=
if command -v restorecon >/dev/null; then restorecon "$dest"; fi
depmod -a "$kver"
[[ $(readlink -f "$(modinfo -k "$kver" -n ixgbe)") == $(readlink -f "$dest") ]]
tmp_initrd=$(mktemp "/boot/.e610-initramfs-${kver}.XXXXXXXX.img")
dracut --force --kver "$kver" --add-drivers ixgbe "$tmp_initrd"
lsinitrd "$tmp_initrd" | grep -F 'updates/drivers/net/ethernet/intel/ixgbe/ixgbe.ko' >/dev/null
mv -f -- "$tmp_initrd" "$initrd"
tmp_initrd=
if command -v restorecon >/dev/null; then restorecon "$initrd"; fi
write_status installed
changed=0
echo '安装完成。当前网口仍使用原驱动，请在维护窗口手动重启。'
echo '回退命令：sudo bash install.sh --rollback'

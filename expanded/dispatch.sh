#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
umask 077
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
kver=$(uname -r)
mode=install
selected_mode=0
die() { echo "错误：$*" >&2; exit 1; }
while (($#)); do
    case "$1" in
        --list|-h|--help) cat "$here/SUPPORTED-SYSTEMS.zh-CN.md"; exit 0 ;;
        --check|--rollback)
            ((selected_mode == 0)) || die '不能同时指定 --check 和 --rollback。'
            selected_mode=1; mode=${1#--} ;;
        --kernel) (($# >= 2)) || exit 2; kver=$2; shift ;;
        *) die "未知参数：$1" ;;
    esac
    shift
done
[[ $(uname -m) == x86_64 ]] || die '仅支持 x86_64 / amd64。'
[[ $kver =~ ^[0-9][a-zA-Z0-9._+-]*$ ]] || die '无效的内核字符串。'
. /etc/os-release
version=$VERSION_ID
[[ $ID != rocky ]] || version=${VERSION_ID%%.*}
case "$ID:$version" in ubuntu:22.04|ubuntu:24.04|rocky:8|rocky:9|centos:7) ;; *) die "未支持的系统：$ID $VERSION_ID" ;; esac
[[ $EUID == 0 ]] || die '请使用 sudo bash 运行。'
[[ -d /lib/modules/$kver ]] || die "系统没有安装目标内核：$kver"
(cd "$here" && sha256sum --status -c SHA256SUMS) || die '统一包内容校验失败。'
kind=
payload=
while IFS=$'\t' read -r os ver kernel action path; do
    [[ $os == "$ID" && $ver == "$version" && $kernel == "$kver" ]] || continue
    [[ -z $kind ]] || die '支持清单存在重复记录。'
    kind=$action; payload=$path
done < "$here/targets.tsv"
native_support() {
    local aliases id
    aliases=$(modinfo -k "$kver" -F alias ixgbe 2>/dev/null) || return 1
    for id in 57AE 57AF 57B0 57B1 57B2; do
        [[ $aliases == *v00008086d0000$id* ]] || return 1
    done
}
if [[ $kind == native || -z $kind ]]; then
    if [[ $mode != rollback ]] && native_support; then
        echo "当前内核 $kver 的有效 ixgbe 模块已经包含 E610 支持，无需额外安装。"
        echo "模块：$(modinfo -k "$kver" -n ixgbe)"
        [[ -n $kind ]] || echo '此内核由本机检测确认设备 ID 支持，未纳入本包的云端测试矩阵。'
        echo '如果仍无网口，请检查 PCI 枚举、驱动加载日志和固件；本次未改动系统。'
        echo "E610_NATIVE_SUPPORT kernel=$kver"
        exit 0
    fi
    [[ $kind != native ]] || die '介质原生支持此内核，但本机有效模块缺失或被旧驱动覆盖；请检查 modinfo -k 内核版本 -n ixgbe。没有改动系统。'
    die "没有匹配 $ID $VERSION_ID / $kver 的离线模块，请提供 uname -rm 以补包。不会更新内核或强行安装。"
fi
echo "E610_MULTIOS_SELECTED=$ID-$version kernel=$kver kind=$kind"
args=(--kernel "$kver")
[[ $mode == install ]] || args+=("--$mode")
case "$kind" in
    legacy) exec bash "$here/$payload" "${args[@]}" ;;
    external) exec bash "$here/$payload/install.sh" "${args[@]}" ;;
    *) die '支持清单格式异常。' ;;
esac

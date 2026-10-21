#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail
export LC_ALL=C
out=$(realpath "${1:?output}")
mode=${2:-stage}
here=$(cd "$(dirname "$0")" && pwd)
bundle=$out/E610-Ubuntu24.04-6.8.0-31
mkdir -p "$bundle/evidence"
grep -q '^E610_SECURE_BOOT_LOAD_PASS kernel=6.8.0-31-generic' "$out/secure-boot.log"
cp "$out/ixgbe.ko" "$out/E610-MOK.der" "$out/certificate.txt" "$out/ixgbe-6.4.5.tar.gz" "$bundle/"
cp "$here/initramfs-hook" "$here/INSTALL.zh-CN.md" "$bundle/"
module_sha=$(sha256sum "$out/ixgbe.ko" | awk '{print $1}')
cert_sha=$(sha256sum "$out/E610-MOK.der" | awk '{print $1}')
sed -e "s/@MODULE_SHA256@/$module_sha/" -e "s/@CERT_SHA256@/$cert_sha/" "$here/install.sh" > "$bundle/install.sh"
chmod 755 "$bundle/install.sh" "$bundle/initramfs-hook"
cp "$out/build.log" "$out/secure-boot.log" "$out/modinfo.txt" "$out/header-packages.txt" "$out/kernel-packages.sha256" "$bundle/evidence/"
git -C "$here" rev-parse HEAD > "$out/build-commit.txt"
python3 - "$out" "$mode" <<'PY'
import hashlib, json, os, pathlib, sys
out = pathlib.Path(sys.argv[1])
bundle = out / 'E610-Ubuntu24.04-6.8.0-31'
manifest = {
 'os': 'Ubuntu 24.04', 'architecture': 'x86_64', 'kernel': '6.8.0-31-generic',
 'driver': 'ixgbe', 'version': '6.4.5',
 'source_url': 'https://github.com/intel/ethernet-linux-ixgbe/releases/download/v6.4.5/ixgbe-6.4.5.tar.gz',
 'source_sha256': '8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4',
 'module_sha256': hashlib.sha256((out/'ixgbe.ko').read_bytes()).hexdigest(),
 'certificate_sha256': hashlib.sha256((out/'E610-MOK.der').read_bytes()).hexdigest(),
 'commit': (out/'build-commit.txt').read_text().strip(),
 'run_url': f"https://github.com/{os.getenv('GITHUB_REPOSITORY','skywalkeramd-org/E610')}/actions/runs/{os.getenv('GITHUB_RUN_ID','local')}",
 'validation': {'compilation': 'passed', 'secure_boot_real_kernel_load_unload': 'passed',
                'unsigned_module_rejected': 'passed',
                'installer_and_rollback': 'passed' if sys.argv[2] == 'release' else 'pending',
                'physical_e610': 'not tested'},
 'signing': 'release-specific MOK; private key deleted in CI; public certificate only',
}
(bundle/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
PY
if [[ $mode == release ]]; then
    grep -q '^E610_INSTALLER_TEST_PASS$' "$out/installer-test.log"
    cp "$out/installer-test.log" "$bundle/evidence/"
    cat > "$bundle/VALIDATION.zh-CN.md" <<'EOF'
# 验证结果

目标：Ubuntu 24.04 amd64，内核 6.8.0-31-generic，Intel ixgbe 6.4.5。

通过：精确内核头文件编译、vermagic、版本及全部五个 E610 PCI 别名。
通过：QEMU/OVMF 开启 Secure Boot，经 Ubuntu 签名 shim、GRUB 启动原版目标内核，
启用内核 lockdown，导入本次公钥到测试机 MOK。
通过：未签名 ixgbe 被拒绝；同次构建的签名 ixgbe 连续三次加载/卸载成功。
虚拟机直接预置 MOK 用于自动化测试，不能替代用户固件上的交互注册步骤。

通过：Ubuntu 24.04 容器内使用真实 depmod、modinfo、mkinitramfs、unmkinitramfs，
检查安装、启动镜像中的签名模块哈希、重复安装、回退、保留已有文件、
损坏包/损坏备份拒绝，以及启动镜像生成失败后的自动恢复。
容器测试使用 --kernel 指定目标，不把容器宿主内核当作目标内核。

未验证：本次没有 E610 实卡，未测试端口 probe、链路、收发、性能、PTP、SR-IOV，
也未测试用户的固件 MOK 界面或完整物理机重启。实机结果须在用户安装后确认。

构建提交和 Actions 链接见 manifest.json；原始日志见 evidence/。
EOF
    cp "$bundle/INSTALL.zh-CN.md" "$bundle/VALIDATION.zh-CN.md" "$bundle/manifest.json" "$out/"
fi
(cd "$bundle" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
if [[ $mode == release ]]; then
    tar --owner=0 --group=0 --numeric-owner -czf "$out/E610-Ubuntu24.04-6.8.0-31-r1.tar.gz" -C "$out" "${bundle##*/}"
    (cd "$out" && sha256sum E610-Ubuntu24.04-6.8.0-31-r1.tar.gz INSTALL.zh-CN.md VALIDATION.zh-CN.md manifest.json > SHA256SUMS)
fi

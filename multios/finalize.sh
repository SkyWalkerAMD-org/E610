#!/bin/bash
set -Eeuo pipefail
out=$(realpath "${1:?output}")
grep -q '^E610_MULTIOS_TEST_PASS target=centos7 kernel=3.10.0-1160.el7.x86_64$' "$out/test-centos7-3.10.0-1160.el7.x86_64.log"
grep -q '^E610_MULTIOS_TEST_PASS target=centos7 kernel=3.10.0-1160.119.1.el7.x86_64$' "$out/test-centos7-3.10.0-1160.119.1.el7.x86_64.log"
grep -q '^E610_MULTIOS_TEST_PASS target=ubuntu22 kernel=5.15.0-78-generic$' "$out/test-ubuntu22.log"
grep -q '^E610_MULTIOS_TEST_PASS target=ubuntu24 kernel=6.8.0-31-generic$' "$out/test-ubuntu24.log"
cat > "$out/VALIDATION.zh-CN.md" <<EOF
# E610 多系统统一包验证

运行：https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID
提交：$GITHUB_SHA

统一包包含三份固定 SHA-256 的已发布单系统 .run，驱动、源码、证书及原安装器保持逐字节一致。
没有重新编译或签名。原有 Ubuntu MOK 注册和系统安装备份可继续使用。

通过：三个系统、四个精确内核分别在相应用户空间中测试，容器禁用网络、无 make/GCC。
通过：实际 ISO 9660 光盘只读挂载，标签 E610_MULTIOS，核对全部介质文件。
通过：root 之外的用户列出支持范围；损坏 .run、未知系统、未知内核、跨系统内核组合拒绝。
通过：tar.gz 直接入口预检查、自动选择正确子包，不解压其他系统的子包。
通过：先用原单系统包安装，再切换到统一入口，保留第一次备份和已安装启动镜像。
通过：回退后从统一 ISO 新安装、核对磁盘模块和启动镜像内容，重复安装保留备份。
通过：被修改的统一缓存拒绝，从保留的本机入口回退，原启动镜像逐字节恢复。

容器使用 --kernel 指定已装入测试环境的目标内核，不能把宿主内核当作目标内核。
模块实际加载及 Ubuntu Secure Boot 验证沿用原发布包记录，链接及摘要见 manifest.json。
虚拟光驱格式和只读挂载已验证，具体 BMC 光驱重定向与固件 MOK 交互没有重新实测。
CentOS 尚无 E610 实卡验收；Ubuntu 22.04.3 先前 PXE 版本有实机记录，新签名包未重新验收；
Ubuntu 24.04 已有安装、重启和基本连通性实机记录，当时 Secure Boot 已关闭。
不覆盖任意内核、10Gbps 吞吐、长时间稳定性、PTP 或 SR-IOV。
EOF
(cd "$out" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 sha256sum > SHA256SUMS)

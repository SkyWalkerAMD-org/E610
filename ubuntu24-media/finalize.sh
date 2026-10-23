#!/bin/bash
set -Eeuo pipefail
out=$(realpath "${1:?output}")
grep -q '^E610_MEDIA_TEST_PASS$' "$out/media-test.log"
cat > "$out/MEDIA-VALIDATION.zh-CN.md" <<EOF
# 离线介质验证

云端运行：https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID
介质代码提交：$GITHUB_SHA

通过：复用已发布 r1 压缩包并核对固定 SHA-256；驱动与 MOK 公钥字节不变。
通过：ISO 9660 / Rock Ridge / Joliet 数据光盘构建，标签 E610_UBU2404。
通过：Linux 只读挂载生成的 ISO，校验全部光盘文件；从光盘启动安装入口。
通过：Ubuntu 24.04 容器禁用网络、未安装 make/GCC，使用真实目标内核模块文件、
depmod、mkinitramfs、unmkinitramfs 完成安装与启动镜像校验。
通过：损坏单文件包拒绝、错误内核拒绝、预检查、重复安装、已修改本机副本拒绝、
从本机保留目录继续执行，以及回退后原启动镜像逐字节恢复。

签名模块在原始发布中已通过真实 6.8.0-31-generic 内核及 QEMU/OVMF Secure Boot
加载测试，本次只增加介质与安装入口，没有重新编译或签名。原验证记录：
https://github.com/SkyWalkerAMD-org/E610/actions/runs/39575285140

未在本次云端测试中验证物理 E610 链路、具体 BMC 的光驱重定向和固件 MOK 交互界面。
该 ISO 供已安装的 Ubuntu 挂载使用，不是系统启动或重装镜像。
EOF
(cd "$out" && sha256sum E610-*.iso E610-*.run KVM-INSTALL.zh-CN.md MEDIA-MANIFEST.json MEDIA-VALIDATION.zh-CN.md media-test.log > MEDIA-SHA256SUMS)

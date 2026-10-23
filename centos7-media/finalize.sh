#!/bin/bash
set -Eeuo pipefail
out=$(realpath "${1:?output}")
for kernel in 3.10.0-1160.el7.x86_64 3.10.0-1160.119.1.el7.x86_64; do
    grep -q "^E610_MEDIA_TEST_PASS kernel=$kernel$" "$out/media-test-$kernel.log"
done
cat > "$out/MEDIA-VALIDATION.zh-CN.md" <<EOF
# CentOS 7.9 离线介质验证

运行：https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID
介质代码提交：$GITHUB_SHA

通过：核对 r2 完整 tar.gz 的固定 SHA-256，模块与源码保持不变。
通过：ISO 9660 / Rock Ridge / Joliet 数据光盘构建，标签 E610_CENTOS7。
通过：实际 ISO 只读挂载并核对全部文件，从光盘入口安装。
通过：两个精确内核分别在 CentOS 7.9 容器中使用真实 kmod、depmod、dracut、
lsinitrd 验证安装、启动镜像模块身份、重复安装、回退和启动镜像逐字节恢复。
通过：测试容器禁用网络且没有 make/GCC；损坏 .run、错误内核、被修改的缓存均拒绝。
通过：从保留的本机目录独立进行预检查和回退。

目标：3.10.0-1160.el7.x86_64、3.10.0-1160.119.1.el7.x86_64。
本次不重新编译或签名。原模块的真实内核 QEMU 加载、三次卸载及缓存清理验证：
https://github.com/SkyWalkerAMD-org/E610/actions/runs/38828112627
原安装器的故障恢复等验证：https://github.com/SkyWalkerAMD-org/E610/actions/runs/38847991201

未验证：E610 实卡链路、收发、性能、PTP、SR-IOV，具体 BMC 光驱重定向。
模块未签名，不支持直接在强制签名的机器安装。ISO 不是系统启动或重装镜像。
EOF
(cd "$out" && sha256sum E610-*.iso E610-*.run KVM-INSTALL.zh-CN.md MEDIA-MANIFEST.json MEDIA-VALIDATION.zh-CN.md media-test-*.log > MEDIA-SHA256SUMS)

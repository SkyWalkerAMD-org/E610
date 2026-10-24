# E610 网卡的 Linux 适配与验证

**[E610 ISO 镜像制作包 6.4.5 r1](https://github.com/SkyWalkerAMD-org/E610/releases/tag/v6.4.5-iso-kit-r1)**：普通手动安装和 PXE 自动安装共用直接内置驱动的 ISO，安装结束自动持久化驱动。包含 38 套精确 ABI 模块、源码和 43 个独立镜像的验证记录（86 项隔离安装与重启）。[制作与使用说明](pxe-media/RELEASE.zh-CN.md)。本轮无 E610 实卡，物理链路、收发及机器 Secure Boot 信任登记仍待验收。

**推荐：[多系统统一离线包 r2](https://github.com/SkyWalkerAMD-org/E610/releases/tag/v6.4.5-multios-r2)**。
一个包覆盖 Ubuntu 22.04 / 24.04、Rocky Linux 8 / 9 的安装介质内核，并保留 CentOS 7.9。
自动匹配系统与精确内核，需要时安装预编译驱动，已经原生支持时提示无需安装，不升级目标内核。
提供 `tar.gz`、`.run` 和 KVM 驱动 ISO；[中文安装说明](expanded/INSTALL.zh-CN.md)。

```bash
sudo bash E610-MultiOS-6.4.5-r2.run
```

**[已适配系统、下载与验证汇总](SUPPORTED-SYSTEMS.zh-CN.md)**：包含精确内核清单、原生支持检测、
中文说明、SHA-256 校验和验证边界。系统大版本相同不代表后续全部安全更新内核均可混用。
原有三系统包及其证书、备份继续沿用。

Ubuntu Server 22.04.3 GA 的构建、镜像适配和验证说明见 [ubuntu22-e610](ubuntu22-e610/README.zh-CN.md)。各系统的编译与实机结果分别记录，不能互相替代。

以下为已发布的 CentOS 7.9 适配。

**CentOS 推荐安装方式：**下载 [CentOS 7.9 Release](https://github.com/skywalkeramd-org/E610/releases/tag/v6.4.5-centos7.9-r2)
中的 r2 完整包，解压后运行 `sudo bash install.sh`。安装器自动选模块、校验、备份并
更新 initramfs；回退使用 `sudo bash uninstall.sh`。具体步骤见
[简化安装说明](INSTALL.zh-CN.md)。下文保留源码构建和手动部署细节。

本项目使用 Intel 官方 ixgbe 6.4.5，目标架构为 x86_64。原始附件与
[Intel 官方发布包](https://github.com/intel/ethernet-linux-ixgbe/releases/tag/v6.4.5)
的 SHA-256 一致：

```text
8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4
```

云端直接下载公开发布包，不上传本地附件。源码已经包含 E610 的 PCI ID：
`8086:57ae`、`8086:57af`、`8086:57b0`、`8086:57b1`、`8086:57b2`。

## 验证范围

目标内核为 `3.10.0-1160.el7.x86_64` 和
`3.10.0-1160.119.1.el7.x86_64`。使用 CentOS 7.9 用户空间、GCC 4.8.5
以及与目标内核完全匹配的 `kernel-devel` 构建。容器宿主机内核不作为目标内核。

编译后检查驱动版本、vermagic、E610 PCI 别名；随后在 QEMU 中启动对应的真实
CentOS 内核，以最小 BusyBox initramfs 加载依赖、加载 ixgbe，再卸载 ixgbe。
每个内核重复三次加载/卸载，并检查 XArray 兼容层的 slab 缓存已释放。
此项验证覆盖内核模块兼容性，不代表完整 CentOS 系统验收。

当前没有 E610 实卡，尚未验证 probe、链路、收发、吞吐、PTP、SR-IOV 或固件交互。
源码中存在这些功能不等于本次已验证这些功能。

## 在目标机器上使用

先检查：

```sh
uname -r
uname -m
lspci -nn | grep -i ethernet
```

仅使用与 `uname -r` 完全相同的构建产物。其他内核版本需要用其对应的
`kernel-devel` 重新编译，不应强制加载不匹配的模块。

云端测试完成后，将所需内核的构建目录复制到目标机器，在该目录检查：

```sh
test "$(uname -m)" = x86_64
test "$(modinfo -F vermagic ./ixgbe.ko | awk '{print $1}')" = "$(uname -r)"
modinfo ./ixgbe.ko
```

安装前备份现有 ixgbe 模块和 initramfs。首次切换驱动请使用本地或带外控制台，
因为 ixgbe 也管理同机上的其他 Intel 网口，卸载或重启可能中断 SSH。确认内核
版本匹配且有恢复途径后，手工安装：

```sh
KVER=$(uname -r)
sudo install -D -m 0644 ./ixgbe.ko "/lib/modules/$KVER/updates/drivers/net/ethernet/intel/ixgbe/ixgbe.ko"
sudo depmod -a "$KVER"
modinfo -n ixgbe
modinfo -F version ixgbe
sudo dracut -f --kver "$KVER"
```

确认 `modinfo -n ixgbe` 解析到新安装的文件，再安排维护窗口重启。以上命令不会
主动卸载正在使用的驱动。本项目生成的模块未签名；若目标机强制验证模块签名，
需按目标机已有的信任链完成签名后安装。

重启后检查网口（将 `IFACE` 替换为实际网口）：

```sh
ethtool -i IFACE
ethtool IFACE
ip -s link show dev IFACE
dmesg | grep -Ei 'ixgbe|firmware|unknown symbol|invalid module'
```

再进行同网段 ping、双向 iperf3、多队列、VLAN/MTU 和长时间收发测试。
PTP、SR-IOV 等功能如需使用，应逐项单独验收。

如需回退，应从带外控制台恢复备份的模块和 initramfs，重新生成对应内核的
depmod 索引，并在维护窗口重启。

## 重现云端测试

在 Linux Docker 主机执行：

```sh
mkdir -p output
docker build --build-arg KVER=3.10.0-1160.119.1.el7.x86_64 -f ci/Dockerfile -t e610-c7 .
docker run --rm -v "$PWD/output:/output" e610-c7
# 主机需有 qemu-system-x86、busybox-static 和 cpio：
bash ci/smoke.sh output
```

日志和模块保存在 `output/`。编译日志有 `E610_BUILD_PASS`、退出码为 0，
且启动日志有 `E610_CLOUD_MODULE_LOAD_PASS`，才算该内核的测试通过。

补丁存放于 `patches/`，按文件名顺序、以 `patch -p1` 应用于官方源码。
完整测试结果以实际云端任务和最终交付的验证报告为准。

## 源码补丁与本机编译

补丁按顺序应用：

1. `0001-centos7-compat.patch`：修正 RHEL 扩展 TC 接口检测、旧 GFP 标志、
   GCC 属性回退、eventfd 头文件及重复 Kconfig 定义。
2. `0002-e610-ptp-compat.patch`：补齐 PTP 延迟工作回退，使用兼容旧版
   `ktime_t` 的时间操作接口。
3. `0003-xarray-lifecycle.patch`：初始化失败或卸载时清理 XArray 缓存，
   清理前等待 RCU 回调完成。

如从官方压缩包构建，在本仓库目录下执行：

```sh
tar -xzf ixgbe-6.4.5.tar.gz
for p in patches/*.patch; do
    patch --batch --fuzz=0 -d ixgbe-6.4.5 -p1 < "$p" || exit 1
done
make -C ixgbe-6.4.5/src -j2 BUILD_KERNEL="$(uname -r)" KSRC="/usr/src/kernels/$(uname -r)"
```

先安装 GCC、make、perl、patch、elfutils-libelf-devel 和与 `uname -r`
完全匹配的 kernel-devel。仅安装 kernel-headers 不能替代 kernel-devel。
`ci/CentOS-Vault.repo` 提供固定的 CentOS 7.9 归档源配置。

本地交付的 `ixgbe-6.4.5-centos7-source.tar.gz` 已应用全部补丁，解压后可直接
运行上述 make 命令，不要再次应用补丁。驱动报告的版本仍为 6.4.5，具体适配
版本通过验证报告中的提交号、补丁 SHA-256 和模块 SHA-256 区分。

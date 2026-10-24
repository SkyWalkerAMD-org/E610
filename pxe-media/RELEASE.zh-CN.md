# E610 ISO Kit 6.4.5 r1

将 E610 驱动直接写入 Linux 安装镜像，普通手动安装和 PXE 自动安装使用同一份 ISO。驱动在安装器收尾时自动写入目标系统，并重建启动 initramfs。

## 下载内容

`E610-ISO-Kit-6.4.5-r1.tar.gz` 是镜像制作工具包，含 38 套精确 ABI 的预编译 ixgbe 6.4.5、公开 MOK 证书、Intel 源码及补丁、制作工具、通用配置预置包、校验清单和公开验证记录。请另行准备具有使用权限的原版系统 ISO，按清单中的发行版目录和文件名存放。

本包没有完整操作系统 ISO，也没有现场密码、授权文件、私钥、生产任务或清盘答案。原有 `E610-MultiOS-6.4.5-r2` 继续用于已安装系统的离线驱动安装；它与本次 ISO 制作工具的用途不同。

## 覆盖与验收

- 43 个不同原版 ISO：AlmaLinux 2、CentOS 8、Debian 7、RHEL 8、Rocky 10、Ubuntu 8。
- 更新既有 CentOS 7.9、Ubuntu 22.04.3 E610 版本，另制作 41 个版本；历史别名复用同一成品。
- 9 个原生支持 E610 的镜像保留原驱动。只匹配实际内核 ABI，不替换或升级内核。
- 38 项原内核加载/卸载检查、9 项归档回归和 86 项手动/PXE 隔离安装、驱动持久化、硬盘重启检查通过。
- 86 项使用可丢弃 QEMU/UEFI 及生成的 PXE 配置；额外进行了真实隔离 iVentoy 传输抽检和 CentOS Stream 10 完整自动安装。
- 当前没有 E610 实卡，本轮未完成物理探测、链路、DHCP/收发、吞吐、PTP、SR-IOV 或机器 Secure Boot 信任登记验收。

逐项结果见 `SUPPORTED-SYSTEMS.zh-CN.md`、`baked-catalog.json` 和 `catalog-evidence.json`。手动路径使用测试专用答案驱动原生安装器，交付镜像不携带这些答案。Ubuntu 24.04.3 的完整安装验收使用普通 GA 6.8.0-71；不宣称其 HWE 目标系统已验收。

## 制作 ISO

在 Linux x86_64 构建机运行，需要 Python >=3.9、xorriso >=1.5.8.pl02、cpio、kmod、gzip/xz/zstd、liblz4/libzstd、openssl；EL 介质还需 implantisomd5/checkisomd5。输出文件系统须支持 reflink。EL10 隐藏 EFI 分区重写需要额外完整镜像空间。无需对发布包中的匹配模块再次编译。

```bash
sha256sum -c SHA256SUMS --ignore-missing
tar -xzf E610-ISO-Kit-6.4.5-r1.tar.gz
cd E610-ISO-Kit-6.4.5-r1
sha256sum -c SHA256SUMS

ISO_ROOT=/data/original-iso
WORK="$PWD/work"
TOOLS="$PWD/source/E610/pxe-media"

# 原版例如 $ISO_ROOT/Debian/debian-12.5.0-amd64-DVD-1.iso。
# 仅放需要处理的原版；工作目录和输出目录必须在原版目录之外。
python3 "$TOOLS/audit.py" --iso-root "$ISO_ROOT" --work "$WORK/audit"
python3 "$TOOLS/assemble_boot.py" --work "$WORK"
python3 "$TOOLS/package_media.py" --work "$WORK" --iso-root "$ISO_ROOT" --out "$WORK/media"

# 用清单中实际文件名替换示例；输出文件必须尚不存在。
python3 "$TOOLS/bake_iso.py" --work "$WORK" --iso-root "$ISO_ROOT" \
  --iso 'Debian/debian-12.5.0-amd64-DVD-1.iso' \
  --out /data/e610-output/debian-12.5.0-amd64-DVD-1-E610.iso
```

审计结果必须是 `needs-injection`，所有涉及内核必须在 `work/drivers` 中精确匹配。`boot-native` 的 ISO 保留原驱动；未知或其他 ABI 不在本包验证范围内。检查原版介质自身的校验和；不要把文件名相同视为内容相同。每次重制后重新做介质检查和安装验收，生成时间等元数据可能导致成品哈希不同。

本轮现场 Ubuntu 24.04.3 原版曾有损坏的 linux-firmware DEB，已单独校验并修复成品，证据随清单保留。该受损输入及其专用修复文件不在本包中；自行构建请使用校验通过的官方原版。本包不会自动猜测或下载修复系统软件包。

若要重新编译驱动，Intel 原版源码位于 `source/ixgbe-6.4.5.tar.gz`，补丁和原构建过程位于 `source/E610/patches`、`source/E610/pxe-media/build_exact.sh`。只能在可丢弃环境里按精确内核头文件、Module.symvers 和对应编译器构建并重新验证；签名私钥未发布。

## 安装后的行为

E610 驱动自动持久化。使用以下命令检查目标系统：

```bash
/usr/local/sbin/ventoy-e610-verify
```

手动安装还会预置通用配置工具，由用户自行执行：

```bash
bash /root/ventoy-linux-setup.run --apply
bash /root/ventoy-linux-setup.run --check
```

该工具配置和检查 SSH、主机名、DHCP、内核锁定及禁用自动更新，保留已有网络设置。配置工具源码随包位于 `source/ventoy`。PXE 自动安装的账号、选盘、RAID/LVM 和配置策略由 Ventoy Center 生成，ISO 不含固定清盘答案。

手动执行 `--apply` 的公开默认初始账号是 `admin / ventoy`、`root / ventoy`，并启用 SSH 密码登录。需要保留已有账号密码时使用 `--keep-passwords`；root 必须已有未锁定的密码。仅预置工具不会自动改账号或网络。

公开 MOK 证书在 `work/drivers/<内核>/E610-MOK.der`。启用 Secure Boot 时按机器信任策略登记对应证书；沿用的未签名模块不能在强制签名环境加载。工具不会自动关闭 Secure Boot，ISO 的原有启动链兼容性也需单独核对。

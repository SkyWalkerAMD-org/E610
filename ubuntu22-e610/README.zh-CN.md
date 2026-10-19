# Ubuntu Server 22.04.3 / Intel E610 适配

目标是原版 `ubuntu-22.04.3-live-server-amd64.iso` 的 **GA 内核
`5.15.0-78-generic`**，驱动为 Intel ixgbe **6.4.5**。不更换内核，不把
CentOS 7 的 `.ko` 放进 Ubuntu，也不应用 `patches/` 中的 CentOS 专用补丁。

现场故障是固件可以通过 E610 网启，但原版 Ubuntu 内核不能识别启动网卡。
iVentoy 随后报告找不到启动 MAC，无法挂载网络 ISO；casper 转而下载已不存在
的在线 ISO 并报 404。修复重点是让 Linux 启动阶段加载匹配内核的 E610 驱动。

## 构建

在 Linux 上准备 Python 3.9+、GCC 11、make、perl、binutils、libelf 开发库、
xorriso、squashfs-tools、cpio、zstd、kmod。镜像构建需要 root，以保留文件属主、
权限和 initramfs 设备节点；脚本不安装构建主机的内核或驱动。

下载 [Intel ixgbe 6.4.5 原始源码](https://github.com/intel/ethernet-linux-ixgbe/releases/tag/v6.4.5)
和 Ubuntu 原版 ISO。脚本核对两者 SHA-256；内核头文件直接取自 ISO，避免混用
其他 ABI。每次指定一个尚不存在的工作目录：

```sh
bash ubuntu22-e610/build_module.sh \
  /path/ubuntu-22.04.3-live-server-amd64.iso \
  /path/ixgbe-6.4.5.tar.gz /work/ubuntu22-module

sudo python3 ubuntu22-e610/build_iso.py \
  --iso /path/ubuntu-22.04.3-live-server-amd64.iso \
  --module /work/ubuntu22-module/output/ixgbe.ko \
  --work /work/ubuntu22-image \
  --output /output/ubuntu-22.04.3-live-server-amd64-E610.iso
```

然后运行实际介质和目标 initramfs 验证（需要 Linux root）：

```sh
sudo bash ubuntu22-e610/validate_image.sh /path/ubuntu-22.04.3-live-server-amd64.iso \
  /output/ubuntu-22.04.3-live-server-amd64-E610.iso /work/ubuntu22-validation
```

输出为 ISO、SHA-256 和构建清单。构建成功不等于实机安装验收；清单的
`hardware_validation` 默认是 `pending`。

## 镜像包含的改动

- 保留原内核、EFI 引导程序、早期 CPU 微码 CPIO 和原始软件包仓库。
- 替换 GA initramfs 和安装环境中的 ixgbe，重新生成模块依赖及 PCI 别名。
- 在两种 Server 安装源共同使用的最小根文件系统层中加入
  `/lib/modules/5.15.0-78-generic/updates/ixgbe.ko`。安装内核软件包后，
  `updates/` 模块优先于发行版自带驱动；initramfs hook 强制包含并校验新模块。
- 手动和自动安装均继承驱动、内核版本 pin、关闭 APT 定时刷新/无人值守升级的
  配置。首次本地启动再建立完整的内核包 hold 清单并复核驱动。
- 安装后的检查命令：`sudo /usr/local/sbin/ventoy-e610-verify` 和
  `sudo /usr/local/sbin/ventoy-center-update-policy --check`。
- 删除此适配镜像中未经适配的 HWE 菜单；原版 ISO 不变。
- 重算介质校验和；移除已修改 squashfs 对应的失效 Ubuntu 签名，保留未修改层
  的签名。产物是自定义镜像，不宣称是 Ubuntu 官方签名镜像。

内核/更新策略脚本来自 Ventoy Center 的已渲染 Ubuntu 策略，随本目录一并提供，
构建无需连接管理后台。ISO 不含机器密码、SSH 私钥、管理令牌或清盘授权。
普通入口仍是手动安装；无人值守需要给这份镜像绑定对应的 PXE 自动安装配置。

## 验证边界

仅覆盖 Ubuntu Server 22.04.3 amd64 的 GA 内核。Desktop、HWE、其他内核 ABI、
Secure Boot 签名加载、PTP、SR-IOV 和高速吞吐需要另行验证。本模块未签名。

发布前应分别核对：编译/符号版本、介质完整性、真实 E610 网启、目标系统驱动
与 initramfs、首次及再次本地启动、DHCP/收发、内核锁定和关闭自动更新。
2026-10-19 已完成 E610 PXE 自动实装及两次本地启动，具体结果见 [实机验证报告](VALIDATION.zh-CN.md)。

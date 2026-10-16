# E610 / CentOS 7.9 简化安装

版本：`v6.4.5-centos7.9-r2`。驱动模块与 r1 相同，本版增加离线安装、备份和回退脚本。

## 安装：下载、解压、执行

从 [Release 页面](https://github.com/skywalkeramd-org/E610/releases/tag/v6.4.5-centos7.9-r2)
下载 **`E610-CentOS7.9-adaptation-r2.tar.gz`**，复制到目标机器。
请使用本地或带外控制台，在维护窗口执行：

```bash
tar -xzf E610-CentOS7.9-adaptation-r2.tar.gz
cd E610-CentOS7.9-adaptation
sudo bash install.sh
```

看到“安装完成”后，在维护窗口手动重启。脚本会自动：

1. 识别系统、架构和当前内核，选择匹配的模块。
2. 校验完整包、模块 SHA-256 和 vermagic。
3. 备份原 initramfs 及已有的同路径更新模块。
4. 安装模块、更新 depmod，并先生成临时 initramfs，成功后替换原文件。
5. 安装失败时尝试自动恢复；重复执行已成功的安装不会覆盖原备份。

安装过程不联网，不需要 GCC 或 kernel-devel。脚本不会卸载当前驱动，也不会自动
重启。ixgbe 可能管理同机其他 Intel 网口，重启切换驱动可能中断网络。

## 回退：一条命令

保留解压目录和 `/var/lib/e610-ixgbe/` 下的备份。在解压目录执行：

```bash
sudo bash uninstall.sh
```

脚本自动查找当前内核最近一次安装的备份，恢复模块及 initramfs。确认成功后在
维护窗口手动重启。重复回退会提示已经恢复，不会删除备份。

## 适用范围

支持 **CentOS Linux 7.9.2009 / x86_64**，以及以下两个精确内核版本：

- `3.10.0-1160.el7.x86_64`
- `3.10.0-1160.119.1.el7.x86_64`

未知内核、文件损坏、vermagic 不匹配时，脚本会停止，不会尝试强制加载。
其他内核需要用匹配的 kernel-devel 从源码构建，见包内 `README.zh-CN.md`。

模块未签名。检测到 Secure Boot 或显式强制模块签名时，安装器会停止。
这类机器应先校验原始文件，再在独立副本上按本机信任链签名，使用手动安装流程；
签名会改变模块摘要，不能直接替换包内模块后再运行本安装器。

两套模块已通过编译和 QEMU 中真实目标内核的加载/卸载检查。安装脚本的测试范围
见 `INSTALLER-VALIDATION.zh-CN.md`。尚无 E610 实卡验证，链路、收发、吞吐、PTP
精度、SR-IOV 和固件交互仍需在实机验收。

## 可选检查

只检查、不安装：

```bash
sudo bash install.sh --check
```

为已安装但当前未运行的受支持内核准备驱动，或从另一个内核执行回退：

```bash
sudo bash install.sh --kernel 3.10.0-1160.119.1.el7.x86_64
sudo bash uninstall.sh --kernel 3.10.0-1160.119.1.el7.x86_64
```

上述两条是不同操作的示例，按需要选择一条执行。

Release 提供外层 `SHA256SUMS`。只下载完整包和校验清单时，在同一目录核对：

```bash
awk '$2 == "E610-CentOS7.9-adaptation-r2.tar.gz"' SHA256SUMS | sha256sum -c -
```

重启后用 `ethtool -i 实际网口名` 检查驱动，并进行链路与收发测试。
驱动上报版本仍为 `6.4.5`，适配修订由 Release 标签及校验值区分。

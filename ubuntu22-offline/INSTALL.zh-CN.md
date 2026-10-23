# Ubuntu 22.04.3 / E610 离线安装

适用范围：**Ubuntu 22.04.3、x86_64、内核 `5.15.0-78-generic`**。驱动为 Intel
原版 ixgbe 6.4.5。无需联网、make、GCC 或内核头文件；保留当前内核。

## 最短安装步骤

在能联网的电脑下载完整包 `E610-Ubuntu22.04.3-5.15.0-78-r1.tar.gz` 和外部
`SHA256SUMS`，校验后用 U 盘或管理控制台复制到目标机 `/root`。
请在本地或带外控制台进行首次安装，重启会中断现有连接。

```bash
cd /root
sha256sum -c SHA256SUMS --ignore-missing
tar -xzf E610-Ubuntu22.04.3-5.15.0-78-r1.tar.gz
cd E610-Ubuntu22.04.3-5.15.0-78
sudo bash install.sh
```

**Secure Boot 已开启时，第一次运行会申请注册本包公钥，暂不替换驱动。**
按提示设置一个一次性密码，然后手动重启：

```bash
sudo reboot
```

在蓝色 MOK 界面选择 `Enroll MOK` → `Continue` → `Yes`，输入刚设置的密码，
再选择 `Reboot`。这不是 Ubuntu 登录密码，也不是关闭 Secure Boot。
若需要确认该界面是否出现，请使用显示器或 BMC 远程控制台。

回到系统后，**再次执行相同安装命令**：

```bash
cd /root/E610-Ubuntu22.04.3-5.15.0-78
sudo bash install.sh
```

出现“安装完成”和 `E610_OFFLINE_INSTALL_PASS` 后再手动重启；保持启动
`5.15.0-78-generic`。若 Secure Boot 已关闭，则第一次运行直接安装，最后重启一次。
安装器不会自动卸载网卡驱动或自动重启。

## 检查结果

```bash
uname -rm
cat /sys/module/ixgbe/version
ip -br link
modinfo -n ixgbe
```

预期内核仍为 `5.15.0-78-generic x86_64`，已加载 ixgbe 版本为 `6.4.5`，
磁盘模块路径位于 `/lib/modules/5.15.0-78-generic/updates/e610/ixgbe.ko`
（Ubuntu 的 `/usr/lib/modules` 等价路径也正常）。
如已安装 ethtool 和 pciutils，还可运行 `ethtool -i 网卡名` 和 `lspci -nnk`。

识别网卡之后仍需按现场网络配置 DHCP 或静态地址；安装器不修改 Netplan、IP、
默认路由或 DNS。请提供新出现的接口名再配置网络，避免覆盖其他网卡设置。

## 预检查与回退

```bash
sudo bash install.sh --check
sudo bash install.sh --rollback
```

安装前自动备份原更新模块（如有）、本包的 initramfs hook（如有）和当前启动镜像，
存放于 `/var/lib/e610-ixgbe/ubuntu22-5.15.0-78-generic/`。
更新失败会尝试恢复这些文件；回退成功后手动重启。
重复安装已安装的同一模块不会覆盖最初备份。

签名证书由本项目为该发布包生成，不是 Intel 或 Ubuntu 官方签名。包中只包含公钥
`E610-MOK.der`，签名私钥在 CI 中使用后删除，没有包含在下载包或仓库中。
证书限制用途为内核模块签名；详细指纹见 `certificate.txt`。
回退驱动不会自动删除 MOK 公钥。需要删除时，可手动执行
`sudo mokutil --delete E610-MOK.der`，重启后确认删除。

## 常见提示

- `mokutil` 崩溃：安装器直接读取 EFI SecureBoot 变量，避免依赖 `--sb-state`；
  证书导入/检查仍需 mokutil 正常工作。若这些操作崩溃，停止并保留报错。
- 未出现 MOK 界面：先检查是否通过 Ubuntu 的 shim 正常启动；不要反复提交导入。
- 缺少系统依赖模块或命令：保留完整报错，以便补齐离线组件；不要混用其他内核的 `.ko`。
- 未出现新网卡：提供 `sudo dmesg | grep -Ei 'ixgbe|firmware|verification|key'`
  和 `lspci -nnk` 输出。虚拟机加载通过不代表真实 E610 链路已经验收。

本包不设置全局 APT hold 或修改系统更新服务；以后切换内核时需要重新编译匹配的模块。

## 来源与验证

- [Intel ixgbe 6.4.5 源码](https://github.com/intel/ethernet-linux-ixgbe/releases/tag/v6.4.5)
- [Ubuntu Secure Boot](https://documentation.ubuntu.com/security/security-features/platform-protections/secure-boot/)
- 包内 `VALIDATION.zh-CN.md`、`manifest.json` 和 `evidence/` 记录本次验证边界。
- GPL 源码原包随包提供；本版本未应用 CentOS 补丁。

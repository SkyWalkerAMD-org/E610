# E610 多系统统一离线安装包

一个包自动识别系统和内核，覆盖三套系统、四个精确内核。驱动为 Intel ixgbe 6.4.5，
沿用各系统已发布的驱动、源码、安装器和签名公钥。无需联网、make、GCC 或内核开发包。

| 系统 | 支持内核 | Secure Boot |
| --- | --- | --- |
| CentOS Linux 7.9.2009 / x86_64 | `3.10.0-1160.el7.x86_64`、`3.10.0-1160.119.1.el7.x86_64` | 驱动未签名，要求关闭且内核不强制模块签名 |
| Ubuntu Server 22.04.3 GA / amd64 | `5.15.0-78-generic` | 使用原 22.04.3 发布包的 MOK 公钥 |
| Ubuntu 24.04 / amd64 | `6.8.0-31-generic` | 使用原 24.04 发布包的 MOK 公钥 |

安装前可执行 `uname -rm` 核对。系统或内核不匹配时停止，不会强制加载其他内核的模块。
不能仅凭“CentOS 7”或“Ubuntu 22.04”就认定任意内核适用。

## 最方便：单文件 .run

下载 `E610-MultiOS-6.4.5-r1.run`，复制到服务器，在文件所在目录执行：

```bash
sudo bash E610-MultiOS-6.4.5-r1.run
```

无需选择系统。看到安装成功后，在维护窗口手动重启。首次切换驱动请使用本地或带外控制台。

## KVM / BMC 挂载 ISO

下载 `E610-MultiOS-6.4.5-r1.iso`，作为虚拟 CD/DVD 连接服务器，进入现有 Linux 后执行：

```bash
sudo mkdir -p /mnt/e610
sudo mount -o ro /dev/sr0 /mnt/e610
sudo bash /mnt/e610/install.sh
```

如有多个光驱，用 `lsblk -o NAME,TYPE,LABEL,MOUNTPOINT` 查找标签 `E610_MULTIOS`。
这是一张驱动数据光盘，用于已安装的系统；无需从光盘启动或重装系统。

## tar.gz 压缩包

```bash
tar -xzf E610-MultiOS-6.4.5-r1.tar.gz
cd E610-MultiOS-6.4.5-r1
sudo bash install.sh
```

三种格式都包含全部三个系统的安装包，实际只运行与当前系统和内核匹配的一份。
`.run` 和 ISO 会保留统一入口到 `/opt/e610-offline/multios-6.4.5-r1/install.sh`。
压缩包直接安装则保留解压目录，后续继续使用其中的 `install.sh`。

## Secure Boot 与重启

Ubuntu 沿用原单系统包的公钥，已注册对应公钥的机器无需重新注册。
两个 Ubuntu 版本的证书不同；统一包没有重新签名或发布私钥。
首次使用且 Secure Boot 开启时，安装器会先申请 MOK 注册，暂不替换驱动：

1. 按提示设置一次性密码，手动重启。
2. 在 MOK 界面选择 `Enroll MOK → Continue → Yes`，输入该密码，完成后重启。
3. 回到系统，再运行同一个安装命令。使用 `.run` 或 ISO 时可直接运行：

```bash
sudo bash /opt/e610-offline/multios-6.4.5-r1/install.sh
```

安装成功后再手动重启。Secure Boot 已关闭或公钥已注册时，通常只需安装后重启一次。
CentOS 部分沿用未签名模块，不会自动调整固件设置。

## 检查和回退

列出支持范围（不需要 root）：

```bash
bash E610-MultiOS-6.4.5-r1.run --list
```

只检查而不安装驱动：

```bash
sudo bash E610-MultiOS-6.4.5-r1.run --check
```

需要回退时，从原解压目录运行 `sudo bash install.sh --rollback`，或使用保留的统一入口：

```bash
sudo bash /opt/e610-offline/multios-6.4.5-r1/install.sh --rollback
sudo reboot
```

统一包调用原系统安装器，沿用已有备份及重复安装检查。已装过单系统同版驱动时，
不会另建一套驱动或覆盖最初备份；文件被修改或缓存损坏时停止并提示。
回退不会自动删除 Ubuntu 的 MOK 公钥。

重启后检查：

```bash
uname -rm
cat /sys/module/ixgbe/version
ip -br link
```

预期内核不变、驱动版本为 `6.4.5`。网卡识别后的 DHCP 或静态地址按现场网络配置。
安装器不自动重启，不更换内核，不修改 IP、路由、DNS 或全局更新策略。

## 校验、源码和验证范围

下载安装包和同一 Release 的 `SHA256SUMS` 后执行：

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

Windows 可使用 `Get-FileHash 文件名 -Algorithm SHA256` 核对。
`manifest.json` 记录三份原包的固定摘要及验证链接；统一包内的 `payloads/` 为原始单系统
安装包，包含各自 GPL 源码和许可证，原始单系统 Release 也继续提供下载。

本次验证重点是自动识别、正确选择、断网安装、只读光盘、重复安装与回退。
真实目标内核加载和 Ubuntu Secure Boot 验证沿用未改变的单系统包记录。
CentOS 尚无 E610 实卡验收；Ubuntu 22.04.3 先前 PXE 版本有实机记录，新签名包未重新实机验收；
Ubuntu 24.04 已验证实机安装、重启和基本连通性。具体结果见 Release 的验证报告，
不能据此认定所有硬件、10Gbps 吞吐、PTP 或 SR-IOV 已验收。

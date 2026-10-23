# E610 已适配系统与下载

所有包均为 **x86_64 / amd64、Intel ixgbe 6.4.5**，安装时保留系统内核。
请先执行 `uname -rm`，选择与内核字符串完全一致的包。系统名称相同但内核不同不能混用。

## 多系统统一包（推荐）

**一个包包含以下全部系统的驱动，自动识别系统和精确内核。** 三种格式任选其一：

- [统一 tar.gz](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-multios-r1/E610-MultiOS-6.4.5-r1.tar.gz)
- [统一 .run](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-multios-r1/E610-MultiOS-6.4.5-r1.run)
- [统一 KVM 驱动 ISO](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-multios-r1/E610-MultiOS-6.4.5-r1.iso)
- [中文安装说明](multios/INSTALL.zh-CN.md) · [SHA-256 校验值](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-multios-r1/SHA256SUMS) · [统一版 Release](https://github.com/SkyWalkerAMD-org/E610/releases/tag/v6.4.5-multios-r1)

复制 `.run` 到服务器后直接执行，无需手动选系统：

```bash
sudo bash E610-MultiOS-6.4.5-r1.run
```

统一包调用下方原始单系统安装器，驱动和签名公钥保持不变，沿用已有备份。
未匹配到表中系统与内核组合时停止。已注册对应 Ubuntu 公钥的机器无需重新注册。
三种格式都包含全部驱动；这里的 ISO 仍为现有系统使用的驱动数据光盘。

## 系统与单系统安装包

| 系统 | 精确支持内核 | 完整 tar.gz | 单文件 .run | KVM 驱动 ISO |
| --- | --- | --- | --- | --- |
| CentOS Linux 7.9.2009 | `3.10.0-1160.el7.x86_64`、`3.10.0-1160.119.1.el7.x86_64` | [下载](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-centos7.9-r2/E610-CentOS7.9-adaptation-r2.tar.gz) | [下载](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-centos7.9-r2/E610-CentOS7.9-adaptation-r2.run) | [下载](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-centos7.9-r2/E610-CentOS7.9-adaptation-r2.iso) |
| Ubuntu Server 22.04.3 GA | `5.15.0-78-generic` | [下载](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-ubuntu22.04.3-5.15.0-78-r1/E610-Ubuntu22.04.3-5.15.0-78-r1.tar.gz) | [下载](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-ubuntu22.04.3-5.15.0-78-r1/E610-Ubuntu22.04.3-5.15.0-78-r1.run) | [下载](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-ubuntu22.04.3-5.15.0-78-r1/E610-Ubuntu22.04.3-5.15.0-78-r1.iso) |
| Ubuntu 24.04 | `6.8.0-31-generic` | [下载](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-ubuntu24.04-6.8.0-31-r1/E610-Ubuntu24.04-6.8.0-31-r1.tar.gz) | [下载](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-ubuntu24.04-6.8.0-31-r1/E610-Ubuntu24.04-6.8.0-31-r1.run) | [下载](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-ubuntu24.04-6.8.0-31-r1/E610-Ubuntu24.04-6.8.0-31-r1.iso) |

三种格式包含同一系统对应的相同驱动，无需联网或编译工具：

- `.run`：复制到服务器后，执行 `sudo bash 文件名.run`。
- KVM ISO：通过 BMC 虚拟 CD/DVD 挂载，进入现有系统后执行光盘中的 `install.sh`。
- `tar.gz`：解压后执行 `sudo bash install.sh`，也便于查看源码、证书及验证日志。

这里的 **KVM ISO 是驱动数据光盘**，不用于启动或重装操作系统。
以前 Ubuntu 22.04.3 的完整 PXE 系统镜像是另一项产物，见 [PXE 适配说明](ubuntu22-e610/README.zh-CN.md)。
GitHub 自动生成的 “Source code” 压缩包仅包含仓库代码，不包含预编译驱动。

## 中文说明与校验

| 系统 | Release | KVM / .run 安装说明 | 三种安装包 SHA-256 |
| --- | --- | --- | --- |
| CentOS 7.9 | [r2](https://github.com/SkyWalkerAMD-org/E610/releases/tag/v6.4.5-centos7.9-r2) | [说明](centos7-media/KVM-INSTALL.zh-CN.md) | [ALL-SHA256SUMS](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-centos7.9-r2/ALL-SHA256SUMS) |
| Ubuntu 22.04.3 | [r1](https://github.com/SkyWalkerAMD-org/E610/releases/tag/v6.4.5-ubuntu22.04.3-5.15.0-78-r1) | [说明](ubuntu22-media/KVM-INSTALL.zh-CN.md) | [ALL-SHA256SUMS](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-ubuntu22.04.3-5.15.0-78-r1/ALL-SHA256SUMS) |
| Ubuntu 24.04 | [r1](https://github.com/SkyWalkerAMD-org/E610/releases/tag/v6.4.5-ubuntu24.04-6.8.0-31-r1) | [说明](ubuntu24-media/KVM-INSTALL.zh-CN.md) | [ALL-SHA256SUMS](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-ubuntu24.04-6.8.0-31-r1/ALL-SHA256SUMS) |

下载所需安装包和同一 Release 的 `ALL-SHA256SUMS` 后，在下载目录执行：

```bash
sha256sum -c ALL-SHA256SUMS --ignore-missing
```

Windows 可使用 `Get-FileHash 文件名 -Algorithm SHA256` 核对。

## 验证情况与限制

| 系统 | 云端验证 | E610 实机验证 | Secure Boot |
| --- | --- | --- | --- |
| CentOS 7.9 | 两套精确内核编译、三次加载/卸载、缓存清理；两套用户空间的离线安装、故障恢复、回退；只读 ISO 安装 | 尚未验证 CentOS 下的 E610 实卡链路和收发 | 模块未签名；要求关闭且内核不强制签名 |
| Ubuntu 22.04.3 | 精确内核编译；真实内核 Secure Boot 加载及未签名模块拒绝；断网安装、故障恢复、回退、只读 ISO 安装 | 先前 PXE 版本已通过 E610 安装、两次重启、DHCP 和局域网收发；本次新签名离线包尚未重新实机验收 | 本次包使用独立 MOK 公钥签名；首次开启需交互注册 |
| Ubuntu 24.04 | 精确内核 Secure Boot 加载及未签名模块拒绝；断网安装、故障恢复、回退、只读 ISO 安装 | 已安装并重启，两个端口识别；一个端口以 1Gbps 全双工连接，DHCP、路由、DNS、HTTPS 通过 | 云端已验证签名加载；实机安装时 Secure Boot 已关闭 |

实机记录：[Ubuntu 22.04.3 PXE](ubuntu22-e610/VALIDATION.zh-CN.md)、[Ubuntu 24.04](ubuntu24-e610/HARDWARE-VALIDATION.zh-CN.md)。
云端记录和构建提交随包附在 `manifest.json`、`MEDIA-MANIFEST.json` 及验证报告中。
基本连通性通过不代表 10Gbps 吞吐、长时间稳定性、PTP 或 SR-IOV 已验收。

安装器不会自动重启，也不会自动修改 IP、DHCP、路由、DNS 或全局系统更新策略。
按提示在维护窗口重启，继续使用对应内核；日后更换内核需匹配的新驱动包。
Ubuntu 的公钥按发布包分别生成，不能用 24.04 包的注册结果代替 22.04.3 包的注册。

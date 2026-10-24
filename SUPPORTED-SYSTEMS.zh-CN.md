# E610 已适配系统与下载

镜像安装适配已发布 **[E610 ISO Kit 6.4.5 r1](https://github.com/SkyWalkerAMD-org/E610/releases/tag/v6.4.5-iso-kit-r1)**，覆盖 AlmaLinux、CentOS、Debian、RHEL、Rocky、Ubuntu 共 43 个需补驱动的原版镜像，手动/PXE 共用成品。详见 [ISO Kit 指南](pxe-media/RELEASE.zh-CN.md)和[逐镜像记录](pxe-media/baked-catalog.json)。以下的 MultiOS r2 清单继续对应已安装系统离线驱动包，两者范围分别列出。

推荐使用 **多系统统一离线包 r2**，支持 x86_64 / amd64，自动匹配系统与精确内核，不升级内核。
覆盖 Ubuntu Server 22.04–22.04.5、24.04–24.04.5 的 GA/HWE 安装介质内核，Rocky Linux 8.4–8.10、9.0–9.8，保留 CentOS 7.9。
不是任意同系列安全更新内核都能混用；完整清单见下表。

## 下载与一键安装

三种格式包含同一套适配内容，任选一种：

- [一键 .run](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-multios-r2/E610-MultiOS-6.4.5-r2.run)
- [完整 tar.gz](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-multios-r2/E610-MultiOS-6.4.5-r2.tar.gz)
- [KVM 驱动 ISO](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-multios-r2/E610-MultiOS-6.4.5-r2.iso)
- [中文安装说明](expanded/INSTALL.zh-CN.md) · [SHA-256 校验值](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-multios-r2/SHA256SUMS) · [最新版 Release](https://github.com/SkyWalkerAMD-org/E610/releases/tag/v6.4.5-multios-r2)

```bash
sudo bash E610-MultiOS-6.4.5-r2.run
```

已经登录 root 时可去掉 `sudo`。无需联网、make、gcc 或内核头文件。
KVM ISO 挂载后执行光盘中的 `install.sh`；这是驱动数据光盘，不用于启动或重装系统。

共 **39 个精确内核组合**：27 个新增签名外部驱动、4 个沿用原包、8 个原生支持。
需要补驱动时安装 ixgbe 6.4.5；原生支持的组合检查本机有效模块后提示无需安装。
原 Ubuntu 22.04.3 GA、Ubuntu 24.04 初始 GA 和 CentOS 7.9 的模块、证书及备份保持不变。

## 统一包的精确支持清单

| 系统 / 安装介质 | 内核 | 处理方式 |
| --- | --- | --- |
| CentOS Linux 7.9 | `3.10.0-1160.el7.x86_64` | 沿用已发布的原包和备份 |
| CentOS Linux 7.9 | `3.10.0-1160.119.1.el7.x86_64` | 沿用已发布的原包和备份 |
| Ubuntu Server 22.04.3 GA | `5.15.0-78-generic` | 沿用已发布的原包和备份 |
| Ubuntu Server 24.04 | `6.8.0-31-generic` | 沿用已发布的原包和备份 |
| Rocky Linux 8.10 | `4.18.0-553.el8_10.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 8.4 | `4.18.0-305.3.1.el8_4.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 8.5 | `4.18.0-348.el8.0.2.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 8.6 | `4.18.0-372.9.1.el8.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 8.7 | `4.18.0-425.3.1.el8.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 8.8 | `4.18.0-477.10.1.el8_8.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 8.9 | `4.18.0-513.5.1.el8_9.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 9.0 | `5.14.0-70.13.1.el9_0.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 9.1 | `5.14.0-162.6.1.el9_1.0.1.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 9.1 | `5.14.0-162.6.1.el9_1.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 9.2 | `5.14.0-284.11.1.el9_2.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 9.3 | `5.14.0-362.8.1.el9_3.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 9.4 | `5.14.0-427.13.1.el9_4.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 9.5 | `5.14.0-503.14.1.el9_5.x86_64` | 离线安装 ixgbe 6.4.5 |
| Rocky Linux 9.6 | `5.14.0-570.17.1.el9_6.x86_64` | 系统原生支持，检查后无需安装 |
| Rocky Linux 9.7 | `5.14.0-611.5.1.el9_7.x86_64` | 系统原生支持，检查后无需安装 |
| Rocky Linux 9.8 | `5.14.0-687.10.1.el9_8.0.1.x86_64` | 系统原生支持，检查后无需安装 |
| Ubuntu Server 22.04 | `5.15.0-25-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 22.04.1 | `5.15.0-43-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 22.04.2 | `5.15.0-60-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 22.04.2 | `5.19.0-32-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 22.04.3 | `6.2.0-26-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 22.04.4 | `5.15.0-94-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 22.04.4 | `6.5.0-18-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 22.04.5 | `5.15.0-119-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 22.04.5 | `6.8.0-40-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 24.04.1 | `6.8.0-41-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 24.04.2 | `6.11.0-17-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 24.04.2 | `6.8.0-53-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 24.04.3 | `6.14.0-27-generic` | 系统原生支持，检查后无需安装 |
| Ubuntu Server 24.04.3 | `6.8.0-71-generic` | 离线安装 ixgbe 6.4.5 |
| Ubuntu Server 24.04.4 | `6.17.0-14-generic` | 系统原生支持，检查后无需安装 |
| Ubuntu Server 24.04.4 | `6.8.0-100-generic` | 系统原生支持，检查后无需安装 |
| Ubuntu Server 24.04.5 | `6.8.0-139-generic` | 系统原生支持，检查后无需安装 |
| Ubuntu Server 24.04.5 | `7.0.0-31-generic` | 系统原生支持，检查后无需安装 |

## 新增适配的验证范围

所有新增内核均启动真实内核验证三次模块加载/卸载；新增外部驱动另外完成 Secure Boot 签名加载、未签名模块拒绝，以及断网、无编译器环境的安装、重复安装、故障恢复和回退测试。
原生支持组合检查原始介质中驱动的全部五个 E610 PCI 设备 ID，并验证模块加载。
最终统一包在 12 个代表性组合中通过只读 ISO、tar.gz、.run 入口、自动选择、完整性校验和回退验证。

[最终成功的发布验证](https://github.com/SkyWalkerAMD-org/E610/actions/runs/39897854153) · [详细验证报告](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-multios-r2/VALIDATION.zh-CN.md) · [产物及内核来源清单](https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-multios-r2/manifest.json)。

新增系统尚未做 E610 实卡链路、吞吐、PTP、SR-IOV 和长时间稳定性验收。旧版本的 Ubuntu 实机记录保留在下方，不能代替新增系统验收。
Ubuntu 22.04 / 22.04.1 的早期内核使用对应原镜像的签名启动链完成 Secure Boot 测试，不表示新版固件或启动器的吊销策略一定接受这些旧内核；安装包不修改启动器。

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

# E610 多系统离线驱动包 r2

适用于 x86_64 / amd64，覆盖 Ubuntu 22.04、24.04 和 Rocky Linux 8、9 安装镜像中的已验证内核，保留 CentOS 7.9 的原有适配。
**精确支持范围见随包的 SUPPORTED-SYSTEMS.zh-CN.md。系统名称相同但内核不同不能强行混用。**

安装器自动识别系统和 `uname -r`。无需联网、make、gcc 或内核头文件，不升级或替换内核，不修改 IP、DHCP、路由，不自动重启或卸载正在使用的网卡驱动。
已经包含 E610 支持的内核会提示无需安装；未覆盖且缺少支持的内核会停止并显示版本。

## 最简单：单文件 .run

下载 `E610-MultiOS-6.4.5-r2.run` 后执行：

```bash
sudo bash E610-MultiOS-6.4.5-r2.run
```

按提示在维护窗口重启，继续启动原内核。查看接口和驱动：

```bash
uname -r
ip -br link
lspci -nnk | grep -A3 -i ethernet
```

外部驱动安装完成后，`cat /sys/module/ixgbe/version` 应显示 `6.4.5`；系统原生驱动的版本显示可能不同。
如果接口已经出现但没有 IP，请按现场网络设置 DHCP 或静态地址；驱动包不覆盖已有网络配置。

## KVM 挂载 ISO

把 `E610-MultiOS-6.4.5-r2.iso` 作为带外 KVM 的虚拟 CD/DVD 挂载。
进入已经安装好的 Linux，执行：

```bash
sudo mkdir -p /mnt/e610
sudo mount -o ro /dev/sr0 /mnt/e610
sudo bash /mnt/e610/install.sh
```

多光驱环境请用 `lsblk -f` 查找标签 `E610_MULTIOS`，替换 `/dev/sr0`。
这是**驱动数据光盘**，不用于启动或重新安装操作系统。
首次运行会把完整包保存在 `/opt/e610-offline/multios-6.4.5-r2`；随后可以卸载、弹出虚拟光驱。

## tar.gz 格式

```bash
tar -xzf E610-MultiOS-6.4.5-r2.tar.gz
cd E610-MultiOS-6.4.5-r2
sudo bash install.sh
```

三种格式内容一致，任选一种即可。

## Secure Boot

Ubuntu 和新增 Rocky 外部模块带有本包的 MOK 签名。
开启 Secure Boot 或内核强制签名时，首次安装可能要求注册**当前内核对应的公钥**：

1. 安装器显示证书校验值，并要求设置一次性密码；此时尚未替换驱动。
2. 重启，在 MOK 界面选择 `Enroll MOK → Continue → Yes`，输入密码并再次重启。
3. 再次执行同一安装命令。如果已经弹出 ISO，可执行下面的本机安装入口。

```bash
sudo bash /opt/e610-offline/multios-6.4.5-r2/install.sh
```

不同新增内核的发布公钥可能不同。原 Ubuntu 22.04.3 / 5.15.0-78 和 Ubuntu 24.04 / 6.8.0-31 继续使用原来的包和公钥，已有注册不受影响。
CentOS 7.9 沿用原未签名模块，要求 Secure Boot 关闭且内核不强制签名。
原生支持的内核无需注册本项目公钥。包内只分发公钥，私钥不上传、不分发。

## 预检查与回退

```bash
sudo bash E610-MultiOS-6.4.5-r2.run --check
sudo bash /opt/e610-offline/multios-6.4.5-r2/install.sh --rollback
```

安装前会备份原模块、对应的启动镜像和本包管理的配置文件；生成新启动镜像失败时自动恢复。
重复执行同一包保留首次备份。回退后在维护窗口重启，不自动删除固件中的 MOK 公钥。
原有三系统包沿用原备份；新增适配的备份位于 `/var/lib/e610-ixgbe/expanded-系统-内核/`。
tar.gz 方式请保留解压目录，用其中的 `install.sh --rollback` 回退。

## 校验与验证范围

下载所需文件及同一 Release 的 `SHA256SUMS`，执行：

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

Windows 可用 `Get-FileHash 文件名 -Algorithm SHA256` 核对。
GitHub 自动生成的 “Source code” 文件不是离线驱动包。

`manifest.json` 记录内核、源码、原安装介质及模块校验值，`evidence/` 保留云端测试日志。
云端验证包括精确内核启动和模块加载；新增外部驱动还验证签名及断网安装、重复安装、故障恢复和回退。
实际测试结论以 `VALIDATION.zh-CN.md` 为准。
虚拟机没有 E610 实卡，不能替代物理链路、10Gbps 吞吐、PTP、SR-IOV 和长时间稳定性测试。
此前 Ubuntu 22.04.3 PXE 版本和 Ubuntu 24.04 / 6.8.0-31 有实机记录，不能视为本次所有新增系统已完成实机验收。

# CentOS 7.9 / E610 一键离线安装与 KVM 光盘

适用：CentOS Linux 7.9.2009 / x86_64，且内核必须为以下之一：

- `3.10.0-1160.el7.x86_64`
- `3.10.0-1160.119.1.el7.x86_64`

三种格式使用已发布 r2 的同一份 ixgbe 6.4.5 驱动，安装器自动选择匹配模块。
无需联网、make、GCC 或内核开发包，保留当前内核。驱动未签名，要求 Secure Boot
关闭且内核不强制模块签名；本包不会修改固件设置。其他内核版本需要单独构建。

## 单文件安装

下载 `E610-CentOS7.9-adaptation-r2.run`，复制到服务器，然后执行：

```bash
sudo bash E610-CentOS7.9-adaptation-r2.run
```

完成后在维护窗口手动重启。首次切换请使用本地或带外控制台。

## KVM / BMC 挂载安装

下载 `E610-CentOS7.9-adaptation-r2.iso`，通过 BMC 的虚拟 CD/DVD 挂载。
这是供现有系统使用的驱动数据光盘，不是系统启动或重装镜像。

```bash
sudo mkdir -p /mnt/e610
sudo mount -o ro /dev/sr0 /mnt/e610
sudo bash /mnt/e610/install.sh
```

如果虚拟光驱不是 `/dev/sr0`，运行 `lsblk -o NAME,TYPE,LABEL,MOUNTPOINT`，
找到标签 `E610_CENTOS7` 对应的设备。光盘已经自动挂载时直接使用实际路径。

## 检查与回退

安装文件自动保留到 `/opt/e610-offline/centos7.9-r2/`，以后不需要光盘。
安装器备份旧模块和启动镜像，遇到错误自动尝试恢复。重复安装保留原备份。
只检查而不安装：

```bash
sudo bash /opt/e610-offline/centos7.9-r2/install.sh --check
```

重启后检查：

```bash
uname -rm
cat /sys/module/ixgbe/version
ip -br link
```

预期内核不变，驱动版本为 `6.4.5`。需要回退时：

```bash
sudo bash /opt/e610-offline/centos7.9-r2/uninstall.sh
sudo reboot
```

本包不修改 IP、DHCP、路由、DNS 或系统更新策略。网卡识别后仍需配置网络。
已通过两套真实内核的云端加载测试，以及两套 CentOS 用户空间的离线安装、
启动镜像和回退测试；尚无 CentOS 下的 E610 实卡链路、收发、性能验收。

## 下载校验

`.run` 和 ISO 的校验见同一 Release 的 `MEDIA-SHA256SUMS`：

```bash
sha256sum -c MEDIA-SHA256SUMS --ignore-missing
```

原 `tar.gz` 的摘要保持不变，见 `SHA256SUMS`。
Windows 可用 `Get-FileHash .\E610-CentOS7.9-adaptation-r2.iso -Algorithm SHA256` 核对。
完整原包说明和两类验证报告也包含在光盘及安装目录中。

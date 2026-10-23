# E610 一键离线安装包与 KVM 光盘

仅适用于 **Ubuntu 24.04、x86_64、内核 `6.8.0-31-generic`**。
驱动为 Intel ixgbe 6.4.5；无需联网、make、GCC 或内核头文件，保留当前内核。
本次介质沿用 r1 已验证的驱动及 MOK 公钥；已经注册该公钥的机器无需重新注册。

## 方式一：KVM / BMC 挂载 ISO

在另一台电脑下载 `E610-Ubuntu24.04-6.8.0-31-r1.iso`，在 KVM / BMC 的
Virtual Media（虚拟介质）中作为 CD/DVD 挂载，连接到服务器。
这是在**现有 Ubuntu 系统中使用的驱动数据光盘**，不用从光盘启动或重装系统。

进入服务器的 Ubuntu 终端，执行：

```bash
sudo mkdir -p /mnt/e610
sudo mount -o ro /dev/sr0 /mnt/e610
sudo bash /mnt/e610/install.sh
```

如果 `/dev/sr0` 不是该虚拟光驱，先运行 `lsblk -o NAME,TYPE,LABEL,MOUNTPOINTS`，
找到标签 `E610_UBU2404` 对应的设备（例如 `/dev/sr1`），替换上面的 `/dev/sr0`。
如果系统已经自动挂载光盘，可直接对其实际挂载路径执行 `sudo bash 路径/install.sh`。
只挂载光盘不会自动安装，需要执行上面的安装命令。

## 方式二：单文件安装包

下载 `E610-Ubuntu24.04-6.8.0-31-r1.run`，复制到服务器，在文件所在目录执行：

```bash
sudo bash E610-Ubuntu24.04-6.8.0-31-r1.run
```

两种方式使用同一份驱动。安装入口会校验并把完整安装文件保存到
`/opt/e610-offline/ubuntu24-6.8.0-31-r1/`，供重启后继续或回退使用。
同一版本重复运行会校验并复用该目录。

## Secure Boot 与重启

**可以保持 Secure Boot 开启。** 首次运行若提示注册证书：

1. 按提示设置一次性 MOK 密码，然后执行 `sudo reboot`。
2. 在 KVM 蓝色 MOK 界面选择 `Enroll MOK` → `Continue` → `Yes`，输入刚设置的密码，再选择 `Reboot`。
3. 回到 Ubuntu 后执行下列命令；此时不用重新挂载光盘，也不用再次复制文件：

```bash
sudo bash /opt/e610-offline/ubuntu24-6.8.0-31-r1/install.sh
```

看到“安装完成”和 `E610_OFFLINE_INSTALL_PASS` 后，再执行 `sudo reboot`。
如果 Secure Boot 已关闭或本包公钥已注册，直接安装成功后重启一次即可。
安装器不会自动重启；首次证书申请阶段尚未替换驱动。

如果没有出现 MOK 界面或导入命令出错，请保留输出，不要反复重装系统。
该模块由项目公钥签名，不是 Intel 或 Ubuntu 官方签名；包内只有公钥，没有私钥。

## 安装后检查与回退

```bash
uname -rm
cat /sys/module/ixgbe/version
ip -br link
```

内核应保持 `6.8.0-31-generic x86_64`，已加载驱动版本应为 `6.4.5`。
网卡识别后仍需按现场网络配置 DHCP 或静态地址，安装器不会修改 IP、路由或 DNS。

需要回退时：

```bash
sudo bash /opt/e610-offline/ubuntu24-6.8.0-31-r1/install.sh --rollback
sudo reboot
```

原模块和启动镜像备份保存在 `/var/lib/e610-ixgbe/ubuntu24-6.8.0-31-generic/`。
完整安装细节、签名信息与原始验证范围见包内 `INSTALL.zh-CN.md`、`certificate.txt`
和 `VALIDATION.zh-CN.md`。后续更换内核需要重新提供对应驱动，本包不设置系统更新策略。

## 下载校验

同一 Release 的 `MEDIA-SHA256SUMS` 提供 ISO、单文件安装包及介质说明的 SHA-256。
在下载文件所在目录运行：

```bash
sha256sum -c MEDIA-SHA256SUMS --ignore-missing
```

Windows PowerShell 可使用 `Get-FileHash .\E610-Ubuntu24.04-6.8.0-31-r1.iso -Algorithm SHA256`
并与 `MEDIA-SHA256SUMS` 中对应行核对。原有 `.tar.gz` 的校验仍见 `SHA256SUMS`。

介质构建和测试信息见 `MEDIA-MANIFEST.json` 及 Release 的 `MEDIA-VALIDATION.zh-CN.md`。
虚拟环境验证不替代 E610 实卡的链路、收发与性能验收。

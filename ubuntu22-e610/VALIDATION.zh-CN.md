# Ubuntu Server 22.04.3 E610 实机验证

验证日期：2026-10-19。结论：**E610 PXE 网启、无人值守实装、首次本地启动及再次重启通过**。

## 验证对象

- Ubuntu Server 22.04.3 amd64，GA 内核 `5.15.0-78-generic`。
- Intel E610，实卡 PCI ID `8086:57b0`，驱动 `ixgbe 6.4.5`。
- MR9540-8i 提供的一块约 960 GB / 893.8 GiB 逻辑盘，UEFI/GPT。
- iVentoy 1.0.45 Pro 配合 Ventoy Center 的 PXE-Auto 入口。

用户在 PXE 中选择适配后的系统，再选择磁盘并输入清盘确认；其后的分区、安装、
配置驱动和更新策略、重启与完成回执自动执行。测试盘原有 CentOS LVM，先按明确
授权单独清理该逻辑盘后继续；通用 PXE 的旧 LVM/RAID 保护没有取消。

## 执行结果

| 检查 | 结果 |
| --- | --- |
| 使用 ISO 内精确版本头文件完整编译 Intel 6.4.5 | 通过，vermagic 正确，5 个 E610 PCI 别名齐全 |
| 原始内核、早期 CPU 微码保留 | 字节比较通过 |
| 全部介质 MD5 校验 | 通过 |
| 真实 squashfs 叠加、目标 initramfs 重建 | 通过，模块 SHA-256 一致 |
| E610 PXE 启动与网络 ISO 挂载 | 通过；原先缺少启动网卡、回落在线 ISO 404 的路径已排除 |
| 自动分区与安装 | 通过；1 GiB EFI 分区，剩余空间 ext4 根分区 |
| 首次本地 UEFI 启动 | 通过；EFI Ubuntu 启动项、磁盘根文件系统、SSH 登录均确认 |
| 再次重启 | 通过；boot ID 已变化，仍从本地盘启动 |
| E610 驱动持久化 | 两次启动均为 ixgbe 6.4.5；模块与 initramfs 内模块哈希一致 |
| E610 DHCP、基本收发 | 两次均获得 DHCP IPv4、可经此网卡 SSH；每次局域网 ping 4 发 4 收 |
| 内核锁定 | 两次均运行 5.15.0-78-generic；已安装内核包 hold，并 pin 阻止引入新 ABI |
| APT 自动刷新及无人值守升级 | 两次检查五个对应 service/timer 均 masked、inactive；APT periodic 设为 0 |
| 首启验证与管理端回执 | 验证服务成功，管理端任务 installed，回执脚本已清除 |
| systemd 失败单元 | 两次均为 0 |

此次实际目标安装了 `linux-image-5.15.0-78-generic` 和
`linux-modules-5.15.0-78-generic` 两个内核包，均为 `5.15.0-78.85` 且被 hold。
镜像叠加验证环境的八个包清单是另一项检查，不能与实机包数量混同。

## 产物与证据

- ISO：`ubuntu-22.04.3-live-server-amd64-E610.iso`，2,137,063,424 字节。
- ISO SHA-256：`a8a8ccda7c3fa9f7643ac09418375f479c3cf1eaccafd2603f54968d8f6bcb80`。
- 模块 SHA-256：`d1f954e9dde92c40d76b5244546ed22922613202b6fd92ea3dc9be9e28944586`。
- [构建清单](validation/build-manifest.json)、[介质检查](validation/image-checks.log)、
  [实机验收摘要](validation/acceptance.json)。公开证据不包含内网地址、机器密码、
  私钥、管理令牌或清盘任务令牌；介质日志中的构建路径已归一化为 `$WORK`。
- 构建清单保留构建时的 `hardware_validation: pending`；构建不会自动宣称实机通过。
  本报告和独立验收摘要记录后续完成的物理机结果。
- Git 仓库提供构建代码和验收记录；ISO 与 `.ko` 为单独构建产物，不存入 Git 源码历史。

## 边界

此次实机通过的是 **Server GA 的 PXE 自动安装流程**。手动安装复用的根文件系统
与驱动持久化已做镜像/目标 initramfs 检查，但没有把另一次全流程手动实装记为通过。
Desktop、HWE、其他内核 ABI、Secure Boot、PTP、SR-IOV、高速吞吐均不在本次结论中。
本模块未签名；不要据此启用 Secure Boot。

安装后可运行：

```sh
uname -r
sudo /usr/local/sbin/ventoy-e610-verify
sudo /usr/local/sbin/ventoy-center-update-policy --check
```

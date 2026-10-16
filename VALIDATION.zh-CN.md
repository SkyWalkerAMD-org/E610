# E610 / CentOS 7.9 云端验证报告

验证日期：2026-10-16（Asia/Tokyo）。

结论：ixgbe 6.4.5 应用本仓库三份补丁后，在下列两个 CentOS 7.9 x86_64
内核上通过编译、模块信息检查，以及实际目标内核中的三次加载/卸载和缓存清理检查。

| 目标内核 | GCC 4.8.5 编译 | E610 PCI 别名 / vermagic | QEMU 内核加载/卸载 | 缓存释放 |
| --- | --- | --- | --- | --- |
| 3.10.0-1160.el7.x86_64 | 通过 | 通过 | 3/3 次通过 | 3/3 次通过 |
| 3.10.0-1160.119.1.el7.x86_64 | 通过 | 通过 | 3/3 次通过 | 3/3 次通过 |

本结论不涵盖 E610 实卡 probe、链路、流量、吞吐、PTP 精度、SR-IOV 或固件操作。
QEMU 没有 E610 设备，启动环境为实际 CentOS 内核和最小 BusyBox initramfs，
并非完整安装的 CentOS 系统。初始化失败路径的清理由代码审查覆盖，未注入故障验证。

## 可核对的云端记录

- 仓库：[skywalkeramd-org/E610](https://github.com/skywalkeramd-org/E610)。
- 已验证代码提交：`6d8c6cc3b2b128fcff0c4177ea59d68bef8a39a3`。
- 最终任务：[38828112627](https://github.com/skywalkeramd-org/E610/actions/runs/38828112627)。
- 初始内核任务：[116740250561](https://github.com/skywalkeramd-org/E610/actions/runs/38828112627/job/116740250561)。
- 最后更新内核任务：[116740250869](https://github.com/skywalkeramd-org/E610/actions/runs/38828112627/job/116740250869)。

仓库中的 `evidence/final/` 保存最终编译、启动、环境和模块信息的文本证据。
对应 `ixgbe.ko` 在该次 Actions 的两个构建产物中，并另行保存在本地交付包中。
Actions 产物保留期为 7 天；仓库文本证据和本地交付文件不依赖该保留期。

## 构建环境与源码

- CentOS Linux 7.9.2009 用户空间。
- GCC `4.8.5-44.el7`，make `3.82-24.el7`，binutils `2.27-44.base.el7_9.1`。
- 每个内核使用同版本 `kernel` 和 `kernel-devel`，使用其 `Module.symvers`。
- 构建显式传入 `BUILD_KERNEL` 和 `KSRC`，不使用容器宿主机内核来选择头文件。
- 内核启用 `CONFIG_MODVERSIONS`；PTP、DCB、SR-IOV、devlink 等默认编译分支保留。
- 模块未签名；QEMU 日志中的外部模块 taint 和缺少签名提示符合预期。
  强制签名的目标机器仍需使用已信任的签名密钥签名。

原始包来自 [Intel 官方 ixgbe 6.4.5 发布](https://github.com/intel/ethernet-linux-ixgbe/releases/tag/v6.4.5)，
其公开发布摘要与用户提供的附件一致：

```text
SHA256 8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4
```

## 修改依据

原版源码在两个内核上都无法编译。云端日志和目标内核头文件确认以下问题：

1. TC 接口检测把 `net_device_ops_extended` 拼写为 `netdevice_ops_extended`，
   误选旧版回调签名，连带造成 `tc_to_netdev.mqprio` 等错误。
2. XArray 兼容代码直接使用旧内核缺少的 `__GFP_DIRECT_RECLAIM`，现回退到
   该内核的 `__GFP_WAIT`。
3. 旧内核没有 `__copy` 属性宏；eventfd 兼容封装缺少所需头文件。
4. E610 PTP 调用缺少 `kthread_mod_delayed_work` 的旧内核工作队列映射，
   并将旧版 union `ktime_t` 当作标量使用。已使用适用两种表示的时间助手接口。
5. XArray 兼容缓存原先没有模块退出清理。现于退出及初始化失败时清理，
   在销毁缓存前等待 RCU 回调完成。首次加载成功后针对该问题补充了重复加载测试。

改动集中在兼容层和 E610 PTP 时间类型处理，没有通过关闭 PTP 来绕过错误。
运行时 PTP 行为仍需实卡验证。

## 后续实卡验收

使用与 `uname -r` 完全一致的模块，按 [中文部署说明](README.zh-CN.md) 安装。
检查 PCI 绑定、驱动版本及 firmware/NVM 信息后，执行链路、双向吞吐、丢包、
VLAN/MTU、多队列及长时间负载测试。PTP 和 SR-IOV 按实际需求另行验证。

驱动上报版本保持为 `6.4.5`；通过本报告的代码提交、补丁和模块 SHA-256
识别适配版本。模块与补丁的实际校验值记录在 `evidence/manifest.json`。

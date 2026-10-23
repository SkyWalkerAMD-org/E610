# 普通 Linux 安装后的 E610 驱动入口

此目录是 Ventoy Center 手动安装完整配置包中 E610 组件的源代码。支持 x86_64 Linux；按真实 PCI 设备、发行版和当前内核选择，不从 ISO 名称猜测驱动。

已原生支持五个 E610 PCI ID 的 ixgbe 保留。确需外部模块时，先使用 E610-MultiOS-6.4.5-r2 中精确匹配的离线模块；没有匹配项时，用 Intel 6.4.5 原始源码和当前内核头文件尝试构建。不会更新内核，也不会加载另一个 ABI 的模块。未知内核构建可能因头文件不可用或源码 API 不兼容而停止，不代表所有内核均已通过验证。

完整系统配置（SSH、主机名、DHCP、锁定内核、关闭自动更新）由 Ventoy Center 提供；本目录只处理驱动。

## 独立使用

先获取并校验 releases 中的 `E610-MultiOS-6.4.5-r2.tar.gz`，解压到本机。该发布包 SHA-256：

`8a3b65589e4b55afef48f6fd797f8c8b08bdb2ec342c3954adfc45d44b686c94`

```bash
sudo bash manual/e610-driver.sh --apply /path/E610-MultiOS-6.4.5-r2
sudo bash manual/e610-driver.sh --check /path/E610-MultiOS-6.4.5-r2
```

在已安装并启动的系统运行。离线禁止安装构建依赖时，使用 `sudo env VC_MANUAL_OFFLINE=1 bash ...`。需要 Python >=2.7（支持 EL8 的 platform-python）解开受校验的旧驱动包，不要求系统预装 tar。

返回 0 表示无 E610 或当前驱动与实际设备绑定检查通过；返回 3 表示需要重启、MOK 注册或设备绑定仍待完成；其他非零表示失败。`E610_NOT_PRESENT` 不能当成硬件驱动验收。

已有工作网卡驱动不会被卸载，也不自动重启。Secure Boot 需要 MOK 时，在真实控制台依安装器提示注册，然后再运行；无人值守上下文只报告待处理。模块和启动镜像有备份及回退，动态构建结果的安装器在 `/var/lib/e610-ixgbe/manual-系统-内核/payload/install.sh`，回退使用它的 `--rollback`。

原始 r2 离线驱动的已有验证以发布说明为准。本次新增验证：三种 legacy 包和 Intel 源码解包、危险路径/链接拒绝、没有 E610 时不替换模块；完整系统包在 Ubuntu 22.04/24.04、Debian 10/13、CentOS 7、Rocky 8 的隔离系统验证。虚拟机不含 E610 实体网卡；其他 Linux 的源码构建路径不是全内核硬件验收承诺。

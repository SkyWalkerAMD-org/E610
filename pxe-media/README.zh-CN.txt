E610 原生安装镜像制作工具

本目录制作的是独立 ISO：驱动直接进入镜像内的启动 initramfs，并通过
发行版原生安装完成钩子复制到目标系统、重建目标 initramfs。
普通手动安装和 PXE 自动安装使用同一份 E610 ISO。
media/ 下的 tar.gz 是中间产物，不能代替最终 ISO 或安装验证。

适配边界
- 精确匹配原版镜像的内核 ABI，不替换内核，不用其他 ABI 的模块冒充。
- 已包含全部 E610 PCI ID 的原生 ixgbe 不覆盖。
- Debian 同时处理文字与 GTK 安装入口；EL 同时处理 EFI/PXE 与
  isolinux 的 initrd；Ubuntu 处理镜像中的 GA/HWE 启动变体。
- 每个 Debian initrd 独立生成模块索引，并保留 lib -> usr/lib 布局、
  原版内置模块和依赖信息；避免 NIC udeb 覆盖后造成显示或其他驱动失效。
- Ubuntu 在原始 init-bottom/ORDER 的唯一 CPIO 记录中增加收尾准备，
  不依赖会被 iVentoy 替换的 /init。只读 casper 模块目录使用独立
  tmpfs 上层的临时 overlay，保留原版模块，确保 live root 仍选中 E610。
- EL 将驱动、索引与钩子合入原始主 CPIO，避免 iVentoy 丢弃追加归档；
  Anaconda 切换根目录前也建立 live 模块覆盖。CentOS 7.9 最终成品通过
  隔离真实 iVentoy UEFI 启动与 ixgbe 6.4.5 加载，28 个 EL 成品重测中。
  EL10 的 initramfs 不含 chroot 时，调用 live 根目录自身的 loader、库
  和 chroot；不混入构建宿主机二进制。修复后的 CentOS Stream 10 已通过
  无硬盘 UEFI 光盘启动至 Anaconda，完整安装结果另行记录。
- Ubuntu Desktop 的原生收尾钩子固定使用真实系统工具路径，避免 Ubiquity
  的兼容 depmod 空实现导致安装后模块索引没有生成。
- 目标系统的正常启动 initramfs 与 EL 救援启动 initramfs均包含驱动。
- 已有自定义模块不同、目标内核未适配或安装验证失败时，停止并报告。
- 新签名模块的公开 MOK 证书随包保存。Secure Boot 启用时必须按机器
  的信任策略登记证书；本工具不自动关闭 Secure Boot。

当前证据见 catalog-evidence.json。
54 个 Linux ISO 中，43 个原版需要补充 E610，9 个启动内核原生支持，
另有 2 个既有专用 ISO。新增制作 41 个，并更新原有 CentOS 7.9 /
Ubuntu 22.04.3 专用版本的完整安装钩子，不增加重复系统版本入口。
复核发现旧 Ubuntu 22.04.3 的 HWE 6.2 内核仍缺 E610；文件名包含
E610 不能代替逐个启动内核与手动安装持久化验收。旧成功镜像保留备份。
38 个精确内核模块已在对应原版内核的隔离虚拟机中完成加载/卸载检查。
这是 ABI 验证，不能代替真实 E610 的探测、链路、DHCP 和收发验收。
当前无 E610 实卡；各 ISO 的完整手动/PXE 安装验收仍须以逐项结果为准。

构建环境
Linux x86_64、Python >=3.9、xorriso、cpio、kmod、gzip/xz/zstd、
liblz4/libzstd、openssl，以及 EL 的 implantisomd5/checkisomd5。
xorriso 推荐 1.5.8.pl02 或更新版本：Rocky 9.1 的隐藏 EFI 引导映像
在 1.5.4 上 replay 失败，已用 1.5.8.pl02 完成重制与介质校验。
可把独立编译版本的 bin 放到 PATH 前面，无需替换宿主机系统软件。
制作输出要求文件系统支持 reflink（例如启用 reflink 的 XFS）。
隐藏 EFI 分区无法原地扩展时，检查可用空间后完整重写 ISO 引导布局。
原版只读打开；输出是不同 inode 的完整 ISO。共享底层数据块不产生
运行时对原版文件路径的依赖。
编译必须在可丢弃的构建环境里执行 build_exact.sh，使用精确头文件、
Module.symvers 和对应编译器。脚本需要 /root/E610-DISPOSABLE-BUILDER
标记，并拒绝在没有该标记的环境中运行。

流程（示例变量自行设置；不能把输出目录设为原版目录）
0. 将本目录的 assets/ 复制到 "$WORK/assets/"，使用同一代码版本。
1. python3 audit.py --iso-root "$ISO_ROOT" --work "$WORK/audit"
   同时输出 inventory.json / inventory-v2.json；后者是后续工具输入。
2. python3 prepare_builds.py --work "$WORK" --iso-root "$ISO_ROOT" \
      --published "$EXTRACTED_E610_RELEASE"
   仅复用精确内核模块。其余内核在隔离环境编译，输出放 drivers/<ABI>。
   build_exact.sh 使用 patches/ 中的补丁；0001-0003 来自既有 CentOS
   适配源码，0004-0006 在本目录。公开证书保留，私钥构建后删除。
3. python3 assemble_boot.py --work "$WORK"
   使用原版模块树生成依赖与覆盖层。
4. smoke_kernels.py 在对应 ISO 内核中验证模块实际加载。
   只有 kernel-smoke-results.json 中通过、且哈希匹配的模块才能打包。
5. python3 package_media.py --work "$WORK" --iso-root "$ISO_ROOT" \
      --out "$WORK/media"
6. 将 Ventoy Center 的 Linux 手动配置预置包保存为
   "$WORK/manual-common.tar.gz"。该包只预置配置工具，不自动运行。
   E610 驱动持久化会在安装结束时执行，不能依赖用户联网后再安装。
7. python3 bake_iso.py --work "$WORK" --iso-root "$ISO_ROOT" \
      --iso "发行版/原版.iso" --out "$OUTPUT/系统版本-E610.iso"
   输出必须不存在。保留引导结构，更新 initrd 文件校验和及 EL 内嵌
   介质校验；回读修改的 initrd，并记录原版/成品 SHA256。
8. 分别完成原生安装器手动流程、PXE 自动流程、硬盘重启验收。
   /usr/local/sbin/ventoy-e610-verify 检查已安装驱动与 initramfs。
   手动安装的通用配置工具位于 /root/ventoy-linux-setup.run，用户运行
   bash /root/ventoy-linux-setup.run --apply 后应用 SSH、DHCP、主机名、
   内核锁定和禁用自动更新策略；其 --check 检查应用结果。

验证本目录的归档解析、唯一启动脚本记录和精简 initramfs 兼容性（8 项）：
  python3 test_media.py

不携带生产密码、私钥、清盘脚本或自动安装答案。制作 ISO 不代表允许
清空任何物理机磁盘；安装目标和磁盘策略由所选安装流程控制。

原版介质完整性
本轮本地 Ubuntu 24.04.3 原版有一个损坏的 linux-firmware 软件包。
已通过官方 ISO 的精确字节范围取得对应软件包，并核对介质 MD5 与包 SHA256。
构建器仅在存在明确修复清单、文件路径/大小和固定 SHA256 全部匹配时，
将该包替换到 E610 输出镜像；原版和其审计证据保留。该可选修复不是驱动注入，
也不替换内核。最终介质及完整安装仍需重新验收。

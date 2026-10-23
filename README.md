# Intel E610 / Linux compatibility

**[Download the multi-system offline package](https://github.com/SkyWalkerAMD-org/E610/releases/tag/v6.4.5-multios-r1)**:
one `.tar.gz`, `.run`, or KVM driver data ISO contains the validated CentOS 7.9,
Ubuntu 22.04.3 and Ubuntu 24.04 installers. It selects the matching OS and exact
kernel automatically and preserves the existing payloads, public signing certificates and backups.
See the [Chinese installation guide](multios/INSTALL.zh-CN.md).

**[Supported systems and downloads / 已适配系统及三种安装包](SUPPORTED-SYSTEMS.zh-CN.md)**

Offline `.tar.gz`, `.run`, and KVM driver data ISO packages are available for
CentOS 7.9 (two exact kernels), Ubuntu Server 22.04.3 GA (`5.15.0-78-generic`),
and Ubuntu 24.04 (`6.8.0-31-generic`). The table includes Chinese instructions,
SHA-256 checksums, and separate cloud and physical hardware validation results.

Ubuntu Server 22.04.3 GA adaptation is developed in [ubuntu22-e610](ubuntu22-e610/README.zh-CN.md). Its build and image checks are separate from CentOS validation; hardware acceptance is recorded there.

[中文说明](README.zh-CN.md) · [Cloud tests](https://github.com/skywalkeramd-org/E610/actions/workflows/centos7.yml)

For CentOS 7.9, download the complete r2 bundle from its [Release](https://github.com/skywalkeramd-org/E610/releases/tag/v6.4.5-centos7.9-r2).
Extract it, then run `sudo bash install.sh` inside the extracted directory. The
offline installer selects the matching kernel module, verifies it, backs up the
existing files and updates initramfs. It does not reboot. Use `sudo bash uninstall.sh`
to restore the backup. See [简化安装说明](INSTALL.zh-CN.md).

Source: Intel's public ixgbe 6.4.5 release, downloaded directly in the cloud. Its
GitHub release asset digest and the user's local archive both have SHA-256
`8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4`.
Upstream: https://github.com/intel/ethernet-linux-ixgbe/releases/tag/v6.4.5

The Git repository contains compatibility patches, installation/test scripts and
validation evidence. Release bundles also contain the adapted source and modules.

The cloud workflow compiles using CentOS 7.9 GCC and the exact CentOS kernel-devel
package, then boots that kernel in QEMU to load/unload the module and its
dependencies. It also repeats module load/unload three times and checks that the
backported XArray slab cache is released. Targets: `3.10.0-1160.el7.x86_64` and
`3.10.0-1160.119.1.el7.x86_64`.

The QEMU check uses a minimal BusyBox initramfs. It checks kernel/module
compatibility, not the full CentOS userspace or E610 hardware. There is no
emulated E610 device. Link, traffic, PTP, SR-IOV and performance require real
hardware tests. Modules are unsigned.

The original driver fails to compile on both targets. Compatibility patches in
`patches/` fix the RHEL extended TC API probe, legacy GFP and compiler definitions,
the eventfd include, E610 PTP work scheduling and ktime handling, and XArray cache
cleanup. They preserve the driver's PTP compilation path. Patch/source licensing
follows the upstream GPL-2.0 license in `COPYING`.

Both targets passed compilation and three load/unload cycles, including cache
cleanup. See the [validation report](VALIDATION.zh-CN.md) and `evidence/final/`.
The exact tested code commit is `6d8c6cc3b2b128fcff0c4177ea59d68bef8a39a3`.
Compiled modules are retained in the successful workflow artifacts for 7 days.

To reproduce on a Linux machine with Docker:

```sh
mkdir -p output
docker build --build-arg KVER=3.10.0-1160.119.1.el7.x86_64 -f ci/Dockerfile -t e610-c7 .
docker run --rm -v "$PWD/output:/output" e610-c7
# Requires qemu-system-x86, busybox-static and cpio on the host:
bash ci/smoke.sh output
```

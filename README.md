# E610 / CentOS 7.9 compatibility

[中文说明](README.zh-CN.md) · [Cloud tests](https://github.com/skywalkeramd-org/E610/actions/workflows/centos7.yml)

Source: Intel's public ixgbe 6.4.5 release, downloaded directly in the cloud. Its
GitHub release asset digest and the user's local archive both have SHA-256
`8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4`.
Upstream: https://github.com/intel/ethernet-linux-ixgbe/releases/tag/v6.4.5

No local source archive is uploaded. This repository contains only the generated
test scripts and, if needed, compatibility patches.

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

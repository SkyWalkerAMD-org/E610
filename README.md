# E610 / CentOS 7.9 compatibility work

Source: Intel's public ixgbe 6.4.5 release, downloaded directly in the cloud. Its
GitHub release asset digest and the user's local archive both have SHA-256
`8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4`.
Upstream: https://github.com/intel/ethernet-linux-ixgbe/releases/tag/v6.4.5

No local source archive is uploaded. This repository contains only the generated
test scripts and, if needed, compatibility patches.

The cloud workflow compiles using CentOS 7.9 GCC and the exact CentOS kernel-devel
package, then boots that kernel in QEMU to load/unload the module and its
dependencies. Targets: `3.10.0-1160.el7.x86_64` and
`3.10.0-1160.119.1.el7.x86_64`.

The QEMU check uses a minimal BusyBox initramfs. It checks kernel/module
compatibility, not the full CentOS userspace or E610 hardware. There is no
emulated E610 device. Link, traffic, PTP, SR-IOV and performance require real
hardware tests. Modules are unsigned.

Initial status: testing the unmodified Intel source. Any compatibility patches
will be stored in `patches/`, with build and boot evidence in workflow artifacts.

To reproduce on a Linux machine with Docker:

```sh
mkdir -p output
docker build --build-arg KVER=3.10.0-1160.119.1.el7.x86_64 -f ci/Dockerfile -t e610-c7 .
docker run --rm -v "$PWD/output:/output" e610-c7
# Requires qemu-system-x86, busybox-static and cpio on the host:
bash ci/smoke.sh output
```

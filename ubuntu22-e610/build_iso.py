#!/usr/bin/env python3
"""Build the E610 variant of the exact Ubuntu Server 22.04.3 GA ISO.

Run as root on Linux in a new, disposable work directory. This modifies files
in that directory only. It neither installs a module on the builder nor changes
any iVentoy configuration. Firmware/EFI boot images and the kernel stay original.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

KERNEL = "5.15.0-78-generic"
ISO_SHA256 = "a4acfda10b18da50e2ec50ccaf860d7f20b389df8765611142305c0e911d16fd"
BASE = "casper/ubuntu-server-minimal.squashfs"
GENERIC = "casper/ubuntu-server-minimal.ubuntu-server.installer.generic.squashfs"
HERE = Path(__file__).resolve().parent


def run(*args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1048576), b""):
            digest.update(block)
    return digest.hexdigest()


def put(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding="utf-8")
    path.chmod(mode)


def copy(source, dest, mode=0o644):
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
    dest.chmod(mode)


def main_offset(data):
    """Keep every early uncompressed CPIO archive, including CPU microcode."""
    pos = 0
    while data[pos:pos + 6] in (b"070701", b"070702"):
        while True:
            header = data[pos:pos + 110]
            if header[:6] not in (b"070701", b"070702"):
                raise ValueError("Invalid early CPIO header")
            namesize = int(header[94:102], 16)
            size = int(header[54:62], 16)
            name = data[pos + 110:pos + 110 + namesize - 1]
            pos = (pos + 110 + namesize + 3) & ~3
            pos = (pos + size + 3) & ~3
            if name == b"TRAILER!!!":
                break
        while pos < len(data) and data[pos] == 0:
            pos += 1
    if data[pos:pos + 4] != b"\x28\xb5\x2f\xfd":
        raise ValueError("Expected Ubuntu 22.04.3 Zstandard initramfs")
    return pos


def replace_module(root, module):
    # A layered squashfs may omit /lib -> usr/lib because its lower layer owns
    # that symlink. depmod still needs a complete path in this isolated layer.
    if not (root / "lib").exists() and (root / "usr/lib").is_dir():
        (root / "lib").symlink_to("usr/lib")
    modules = root / "lib/modules" / KERNEL
    old = modules / "kernel/drivers/net/ethernet/intel/ixgbe/ixgbe.ko"
    if not old.is_file():
        raise ValueError("Expected stock ixgbe module: " + str(old))
    copy(module, old)
    # The GA layer marks its kernel directory opaque; include the override
    # here as well as in the install-source base layer.
    copy(module, modules / "updates/ixgbe.ko")
    run("depmod", "-b", root, KERNEL)
    aliases = (modules / "modules.alias").read_text()
    if "pci:v00008086d000057B0" not in aliases:
        raise ValueError("E610 alias absent after depmod")


def build(iso, module, policy, work, output):
    if os.geteuid() != 0:
        raise ValueError("Root required to preserve squashfs ownership and permissions")
    os.umask(0o022)
    if sha(iso) != ISO_SHA256:
        raise ValueError("This builder accepts only the verified Ubuntu 22.04.3 ISO")
    for field, expected in (("version", "6.4.5"), ("vermagic", KERNEL)):
        value = subprocess.check_output(["modinfo", "-F", field, str(module)], text=True).strip()
        if (value.split()[0] if field == "vermagic" else value) != expected:
            raise ValueError("Unexpected module " + field)
    if "{{" in policy.read_text() or "Kernel/update policy" not in policy.read_text():
        raise ValueError("Pass a rendered, validated linux-update-policy.sh")
    work.mkdir(parents=True, exist_ok=False)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise ValueError("Refusing to replace an existing output ISO")
    original = work / "original"
    mapped = work / "mapped"
    original.mkdir()
    mapped.mkdir()
    paths = [BASE, GENERIC, "casper/initrd", "casper/install-sources.yaml", "md5sum.txt", "boot/grub/grub.cfg", "boot/grub/loopback.cfg"]
    for path in paths:
        dest = original / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        run("xorriso", "-osirrox", "on", "-indev", iso, "-extract", "/" + path, dest)
    for path, name in ((BASE, "base"), (GENERIC, "generic")):
        run("unsquashfs", "-no-progress", "-processors", "4", "-d", work / name, original / path)

    data = (original / "casper/initrd").read_bytes()
    offset = main_offset(data)
    archive = work / "initrd.cpio"
    with archive.open("wb") as stream:
        run("zstd", "-d", "-c", input=data[offset:], stdout=stream)
    initrd = work / "initrd"
    initrd.mkdir()
    with archive.open("rb") as stream:
        run("cpio", "--extract", "--make-directories", "--preserve-modification-time", "--no-absolute-filenames", stdin=stream, cwd=initrd)
    replace_module(initrd, module)
    replace_module(work / "generic", module)
    names = sorted(p.relative_to(initrd).as_posix() for p in initrd.rglob("*"))
    with (work / "new-initrd.cpio").open("wb") as stream:
        run("cpio", "--create", "--null", "--format=newc", input=("\0".join(names) + "\0").encode(), stdout=stream, cwd=initrd)
    (mapped / "casper").mkdir()
    with (mapped / "casper/initrd").open("wb") as stream:
        stream.write(data[:offset])
        run("zstd", "-T4", "-3", "-c", work / "new-initrd.cpio", stdout=stream)

    # Minimal is the common lower layer for BOTH manual installation sources.
    # The kernel's dpkg postinst runs depmod and update-initramfs after extraction;
    # updates/ wins over the stock module installed by linux-modules-extra.
    root = work / "base"
    payload = root / "usr/share/ventoy-e610"
    copy(module, root / "lib/modules" / KERNEL / "updates/ixgbe.ko")
    put(payload / "module.sha256", sha(module) + "\n")
    put(payload / "kernel", KERNEL + "\n")
    copy(policy, root / "usr/local/sbin/ventoy-center-update-policy", 0o755)
    copy(HERE / "initramfs-hook.sh", root / "usr/share/initramfs-tools/hooks/ventoy-e610", 0o755)
    copy(HERE / "verify.sh", root / "usr/local/sbin/ventoy-e610-verify", 0o755)
    copy(HERE / "first-boot.sh", root / "usr/local/sbin/ventoy-e610-first-boot", 0o755)
    put(root / "etc/systemd/system/ventoy-e610-first-boot.service", """[Unit]
Description=Verify E610 driver and enforce the installation kernel policy
After=local-fs.target
Before=ventoy-center-bootstrap.service
ConditionPathExists=!/run/casper
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ventoy-e610-first-boot
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
""")
    wants = root / "etc/systemd/system/multi-user.target.wants/ventoy-e610-first-boot.service"
    wants.parent.mkdir(parents=True, exist_ok=True)
    wants.symlink_to("../ventoy-e610-first-boot.service")
    # Block online kernel substitution and automatic package upgrades during a
    # manual install too. First boot adds holds for the installed package set.
    pins = ""
    for packages, version in (
        ("linux-image-5.15.0-78-generic linux-modules-5.15.0-78-generic linux-modules-extra-5.15.0-78-generic linux-headers-5.15.0-78 linux-headers-5.15.0-78-generic", "5.15.0-78.85"),
        ("linux-generic linux-image-generic linux-headers-generic", "5.15.0.78.75"),
    ):
        pins += f"Package: {packages}\nPin: version {version}\nPin-Priority: 1001\n\n"
    pins += "Package: linux-image* linux-modules* linux-headers* linux-generic* linux-virtual* linux-lowlatency* linux-oem* linux-aws* linux-azure* linux-gcp* linux-oracle*\nPin: version *\nPin-Priority: -1\n"
    put(root / "etc/apt/preferences.d/01-ventoy-e610-ga-kernel", pins)
    put(root / "etc/apt/apt.conf.d/99-ventoy-e610-no-auto-updates", """APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
Unattended-Upgrade::Package-Blacklist { ".*"; };
""")
    for unit in ("apt-daily.timer", "apt-daily-upgrade.timer", "apt-daily.service", "apt-daily-upgrade.service", "unattended-upgrades.service"):
        dest = root / "etc/systemd/system" / unit
        if dest.exists() or dest.is_symlink():
            raise ValueError("Unexpected preexisting unit override: " + str(dest))
        dest.symlink_to("/dev/null")

    for path, name in ((BASE, "base"), (GENERIC, "generic")):
        dest = mapped / path
        run("mksquashfs", work / name, dest, "-noappend", "-comp", "xz", "-processors", "4", "-no-progress")
        size = sum(p.stat().st_size for p in (work / name).rglob("*") if p.is_file() and not p.is_symlink())
        put(dest.with_suffix(".size"), str(size) + "\n")
    for path in ("boot/grub/grub.cfg", "boot/grub/loopback.cfg"):
        text = (original / path).read_text()
        text, count = re.subn(r'menuentry "Ubuntu Server with the HWE kernel" \{.*?\n\}', "", text, flags=re.S)
        if count != 1:
            raise ValueError("Unexpected HWE menu; adapt only the GA kernel")
        text = text.replace("Try or Install Ubuntu Server", "Ubuntu Server 22.04.3 - Intel E610 - GA 5.15.0-78")
        put(mapped / path, text)
    # Changed squashfs files are custom artifacts; do not retain invalid Ubuntu
    # signatures. The untouched layers retain their original signatures.
    removed = {BASE + ".gpg", GENERIC + ".gpg"}
    checksums = {}
    for line in (original / "md5sum.txt").read_text().splitlines():
        digest, path = line.split(maxsplit=1)
        path = path.removeprefix("*").removeprefix("./")
        if path not in removed:
            checksums[path] = digest
    for path in mapped.rglob("*"):
        if path.is_file():
            checksums[path.relative_to(mapped).as_posix()] = hashlib.md5(path.read_bytes()).hexdigest()
    put(mapped / "md5sum.txt", "".join(digest + "  ./" + path + "\n" for path, digest in sorted(checksums.items())))
    args = ["xorriso", "-indev", iso, "-outdev", output, "-boot_image", "any", "replay"]
    for path in sorted(mapped.rglob("*")):
        if path.is_file():
            args += ["-map", path, "/" + path.relative_to(mapped).as_posix()]
    for path in sorted(removed):
        args += ["-rm", "/" + path, "--"]
    run(*args, "-commit", "-end")
    manifest = {"source_iso_sha256": ISO_SHA256, "output_iso": output.name, "output_iso_sha256": sha(output),
                "kernel": KERNEL, "driver": "ixgbe 6.4.5", "module_sha256": sha(module), "policy_sha256": sha(policy),
                "source_reference": "https://github.com/SkyWalkerAMD-org/E610/releases/tag/v6.4.5-centos7.9-r2",
                "signature": "unsigned custom module; Secure Boot hardware validation not included",
                "hardware_validation": "pending"}
    put(output.with_suffix(".manifest.json"), json.dumps(manifest, indent=2) + "\n")
    put(output.with_suffix(".iso.sha256"), manifest["output_iso_sha256"] + "  " + output.name + "\n")
    print(json.dumps(manifest, indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("iso", "module", "work", "output"):
        parser.add_argument("--" + option, type=Path, required=True)
    parser.add_argument("--policy", type=Path, default=HERE / "linux-update-policy.sh")
    opts = parser.parse_args()
    build(*(getattr(opts, name).resolve() for name in ("iso", "module", "policy", "work", "output")))

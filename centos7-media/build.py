#!/usr/bin/env python3
"""Wrap the unchanged, hash-pinned CentOS 7.9 r2 release as .run and data ISO."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
NAME = "E610-CentOS7.9-adaptation-r2"
ARCHIVE_SHA = "43b88ce14c6e6ddd41d99559b6fcd58c043fd6bc389e37113f7cee01eeeb308c"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, text):
    path.write_text(text, encoding="utf-8", newline="\n")


def checksums(directory):
    write(directory / "MEDIA-SHA256SUMS", "".join(
        f"{sha(p)}  {p.relative_to(directory).as_posix()}\n"
        for p in sorted(directory.rglob("*")) if p.is_file() and p.name != "MEDIA-SHA256SUMS"
    ))


def main(archive, work, output):
    if sha(archive) != ARCHIVE_SHA:
        raise ValueError("Expected the unchanged CentOS 7.9 r2 release archive")
    work.mkdir(parents=True, exist_ok=False)
    output.mkdir(parents=True, exist_ok=False)
    extracted = work / "extracted"
    extracted.mkdir()
    with tarfile.open(archive) as source:
        source.extractall(extracted, filter="data")
    bundle = extracted / "E610-CentOS7.9-adaptation"
    subprocess.run(["sha256sum", "--status", "-c", "SHA256SUMS"], cwd=bundle, check=True)
    payload = json.loads((bundle / "manifest.json").read_text())
    for module in payload["modules"]:
        if sha(bundle / f"ixgbe-6.4.5-{module['kernel']}" / "ixgbe.ko") != module["sha256"]:
            raise ValueError("Module differs from the validated release")
    media = work / "iso-root"
    media.mkdir()
    header = (HERE / "launcher.sh.in").read_text(encoding="utf-8")
    header = header.replace("@ARCHIVE_SHA256@", ARCHIVE_SHA)
    header = header.replace("@PAYLOAD_LINE@", str(header.count("\n") + 1))
    installer = media / (NAME + ".run")
    installer.write_bytes(header.encode("utf-8") + archive.read_bytes())
    installer.chmod(0o755)
    for name in ("install.sh", "KVM-INSTALL.zh-CN.md"):
        shutil.copyfile(HERE / name, media / name)
    (media / "install.sh").chmod(0o755)
    for name in ("INSTALL.zh-CN.md", "VALIDATION.zh-CN.md", "INSTALLER-VALIDATION.zh-CN.md"):
        shutil.copyfile(bundle / name, media / name)
    manifest = {
        "os": "CentOS Linux 7.9.2009", "architecture": "x86_64", "driver": "ixgbe 6.4.5",
        "modules": payload["modules"], "module_signing": "unsigned",
        "media_type": "ISO 9660 data CD; Rock Ridge and Joliet; not bootable",
        "volume_label": "E610_CENTOS7", "network_required_on_target": False,
        "compiler_required_on_target": False, "kernel_replaced": False,
        "persistent_package": "/opt/e610-offline/centos7.9-r2",
        "archive_url": "https://github.com/SkyWalkerAMD-org/E610/releases/download/v6.4.5-centos7.9-r2/" + NAME + ".tar.gz",
        "archive_sha256": ARCHIVE_SHA, "payload_commit": payload["tested_commit"],
        "payload_validation": payload["run_url"], "installer_validation": payload["installer"]["run_url"],
        "media_commit": os.environ["GITHUB_SHA"],
        "media_run": "https://github.com/SkyWalkerAMD-org/E610/actions/runs/" + os.environ["GITHUB_RUN_ID"],
        "run_sha256": sha(installer), "physical_e610_validation": "not tested",
    }
    write(media / "MEDIA-MANIFEST.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    checksums(media)
    subprocess.run(["xorriso", "-as", "mkisofs", "-iso-level", "3", "-r", "-J", "-joliet-long",
                    "-V", "E610_CENTOS7", "-o", str(output / (NAME + ".iso")), str(media)], check=True)
    for name in (NAME + ".run", "KVM-INSTALL.zh-CN.md", "MEDIA-MANIFEST.json"):
        shutil.copyfile(media / name, output / name)
    checksums(output)
    print("E610_MEDIA_BUILD_PASS", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("archive", "work", "output"):
        parser.add_argument("--" + option, type=Path, required=True)
    args = parser.parse_args()
    main(args.archive.resolve(), args.work.resolve(), args.output.resolve())

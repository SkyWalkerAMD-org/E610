#!/usr/bin/env python3
"""Combine the three unchanged public installers with an OS/kernel dispatcher."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
NAME = "E610-MultiOS-6.4.5-r1"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, content):
    path.write_text(content, encoding="utf-8", newline="\n")


def checksums(directory, filename="SHA256SUMS"):
    write(directory / filename, "".join(
        f"{sha(p)}  {p.relative_to(directory).as_posix()}\n"
        for p in sorted(directory.rglob("*")) if p.is_file() and p.name != filename
    ))


def main(work, output):
    work.mkdir(parents=True, exist_ok=False)
    output.mkdir(parents=True, exist_ok=False)
    bundle = work / NAME
    (bundle / "payloads").mkdir(parents=True)
    targets = json.loads((HERE / "payloads.json").read_text())
    script = (HERE / "install.sh.in").read_text()
    for key, payload in targets.items():
        url = ("https://github.com/SkyWalkerAMD-org/E610/releases/download/"
               + payload["release"] + "/" + payload["file"])
        target = bundle / "payloads" / payload["file"]
        subprocess.run(["curl", "--fail", "--location", "--retry", "3", "-o", str(target), url], check=True)
        if sha(target) != payload["sha256"]:
            raise ValueError(f"Published payload changed: {key}")
        payload["url"] = url
        script = script.replace(f"@{key.upper()}_SHA256@", payload["sha256"])
    if "_SHA256@" in script:
        raise ValueError("Unrendered dispatcher")
    write(bundle / "install.sh", script)
    (bundle / "install.sh").chmod(0o755)
    shutil.copyfile(HERE / "INSTALL.zh-CN.md", bundle / "INSTALL.zh-CN.md")
    manifest = {
        "package": NAME, "architecture": "x86_64", "driver": "ixgbe 6.4.5",
        "targets": targets, "payloads_rebuilt_or_resigned": False,
        "network_required_on_target": False, "compiler_required_on_target": False,
        "kernel_replaced": False, "volume_label": "E610_MULTIOS",
        "media_type": "ISO 9660 driver data disc; not bootable",
        "persistent_package": "/opt/e610-offline/multios-6.4.5-r1",
        "commit": os.environ["GITHUB_SHA"],
        "run_url": f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
        "validation_report": "See external VALIDATION.zh-CN.md generated only after all four target tests pass",
    }
    write(bundle / "manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    checksums(bundle)
    archive = output / (NAME + ".tar.gz")
    subprocess.run(["tar", "--owner=0", "--group=0", "--numeric-owner", "-czf", str(archive),
                    "-C", str(work), NAME], check=True)
    header = (HERE / "launcher.sh.in").read_text()
    header = header.replace("@ARCHIVE_SHA256@", sha(archive))
    header = header.replace("@PAYLOAD_LINE@", str(header.count("\n") + 1))
    if "@ARCHIVE_" in header or "@PAYLOAD_" in header:
        raise ValueError("Unrendered launcher")
    installer = output / (NAME + ".run")
    installer.write_bytes(header.encode() + archive.read_bytes())
    installer.chmod(0o755)
    media = work / "iso-root"
    media.mkdir()
    shutil.copyfile(installer, media / installer.name)
    shutil.copyfile(HERE / "iso-install.sh", media / "install.sh")
    (media / "install.sh").chmod(0o755)
    for name in ("INSTALL.zh-CN.md", "manifest.json"):
        shutil.copyfile(bundle / name, media / name)
        shutil.copyfile(bundle / name, output / name)
    checksums(media)
    subprocess.run(["xorriso", "-as", "mkisofs", "-iso-level", "3", "-r", "-J", "-joliet-long",
                    "-V", "E610_MULTIOS", "-o", str(output / (NAME + ".iso")), str(media)], check=True)
    checksums(output)
    print("E610_MULTIOS_BUILD_PASS", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("work", "output"):
        parser.add_argument("--" + option, type=Path, required=True)
    args = parser.parse_args()
    main(args.work.resolve(), args.output.resolve())

#!/usr/bin/env python3
"""Wrap the already released, signed driver in a .run installer and data ISO."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
NAME = "E610-Ubuntu24.04-6.8.0-31-r1"
ARCHIVE_SHA = "7d18574ea915f452c69e0c152be2df18261fc3b709183994dede2b35de9d550e"
MODULE_SHA = "846e8c45328507d3474019611e5ce4f1c40a7f20875b2b05c4645a15358ca9e1"
CERT_SHA = "895376179044eb32c24da6c6df6c3f0b94c0650c030dc54797012bf0a6adde57"
SOURCE_COMMIT = "6af1494ab7064e498bf4cef051e9ea1c80139ebb"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, text):
    path.write_text(text, encoding="utf-8", newline="\n")


def checksums(directory, filename):
    write(directory / filename, "".join(
        f"{sha(p)}  {p.relative_to(directory).as_posix()}\n"
        for p in sorted(directory.rglob("*")) if p.is_file() and p.name != filename
    ))


def main(archive, work, output):
    if sha(archive) != ARCHIVE_SHA:
        raise ValueError("Only the verified r1 archive may be wrapped")
    work.mkdir(parents=True, exist_ok=False)
    output.mkdir(parents=True, exist_ok=False)
    extracted = work / "extracted"
    extracted.mkdir()
    with tarfile.open(archive) as source:
        source.extractall(extracted, filter="data")
    bundle = extracted / "E610-Ubuntu24.04-6.8.0-31"
    subprocess.run(["sha256sum", "--status", "-c", "SHA256SUMS"], cwd=bundle, check=True)
    if sha(bundle / "ixgbe.ko") != MODULE_SHA or sha(bundle / "E610-MOK.der") != CERT_SHA:
        raise ValueError("Signed module or certificate differs from the validated release")
    media = work / "iso-root"
    media.mkdir()
    header = (HERE / "launcher.sh.in").read_text(encoding="utf-8")
    header = header.replace("@ARCHIVE_SHA256@", ARCHIVE_SHA)
    header = header.replace("@PAYLOAD_LINE@", str(header.count("\n") + 1))
    if "@ARCHIVE_" in header or "@PAYLOAD_" in header:
        raise ValueError("Unrendered launcher")
    installer = media / (NAME + ".run")
    installer.write_bytes(header.encode("utf-8") + archive.read_bytes())
    installer.chmod(0o755)
    shutil.copyfile(HERE / "install.sh", media / "install.sh")
    (media / "install.sh").chmod(0o755)
    shutil.copyfile(HERE / "KVM-INSTALL.zh-CN.md", media / "KVM-INSTALL.zh-CN.md")
    for name in ("INSTALL.zh-CN.md", "VALIDATION.zh-CN.md", "certificate.txt", "E610-MOK.der"):
        shutil.copyfile(bundle / name, media / name)
    manifest = {
        "os": "Ubuntu 24.04", "architecture": "x86_64", "kernel": "6.8.0-31-generic",
        "driver": "ixgbe 6.4.5", "media_type": "ISO 9660 data CD; Rock Ridge and Joliet; not bootable",
        "volume_label": "E610_UBU2404", "network_required_on_target": False,
        "compiler_required_on_target": False, "kernel_replaced": False,
        "persistent_package": "/opt/e610-offline/ubuntu24-6.8.0-31-r1",
        "archive_url": "https://github.com/SkyWalkerAMD-org/E610/releases/download/"
                       "v6.4.5-ubuntu24.04-6.8.0-31-r1/" + NAME + ".tar.gz",
        "archive_sha256": ARCHIVE_SHA, "module_sha256": MODULE_SHA,
        "certificate_sha256": CERT_SHA, "signed_payload_commit": SOURCE_COMMIT,
        "signed_payload_validation": "https://github.com/SkyWalkerAMD-org/E610/actions/runs/39575285140",
        "media_commit": os.environ.get("GITHUB_SHA", "local"),
        "media_run": "https://github.com/SkyWalkerAMD-org/E610/actions/runs/" + os.environ.get("GITHUB_RUN_ID", "local"),
        "run_sha256": sha(installer), "physical_e610_validation": "not tested",
    }
    write(media / "MEDIA-MANIFEST.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    checksums(media, "MEDIA-SHA256SUMS")
    subprocess.run([
        "xorriso", "-as", "mkisofs", "-iso-level", "3", "-r", "-J", "-joliet-long",
        "-V", "E610_UBU2404", "-o", str(output / (NAME + ".iso")), str(media),
    ], check=True)
    for name in (NAME + ".run", "KVM-INSTALL.zh-CN.md", "MEDIA-MANIFEST.json"):
        shutil.copyfile(media / name, output / name)
    checksums(output, "MEDIA-SHA256SUMS")
    print("E610_MEDIA_BUILD_PASS", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("archive", "work", "output"):
        parser.add_argument("--" + option, type=Path, required=True)
    args = parser.parse_args()
    main(args.archive.resolve(), args.work.resolve(), args.output.resolve())

#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path
import shutil
import sys

HERE = Path(__file__).resolve().parent


def checksums(directory):
    lines = []
    for p in sorted(directory.rglob('*')):
        if p.is_file() and p.name != 'SHA256SUMS':
            digest = hashlib.sha256(p.read_bytes()).hexdigest()
            lines.append(f'{digest}  {p.relative_to(directory).as_posix()}\n')
    (directory / 'SHA256SUMS').write_text(''.join(lines))


def stage(out):
    target = json.loads((out / 'target.json').read_text())
    if target['native']:
        return
    dest = out / 'payload'
    dest.mkdir(exist_ok=True)
    for name in ('ixgbe.ko', 'E610-MOK.der', 'target.json'):
        shutil.copyfile(out / name, dest / name)
    shutil.copyfile(HERE / 'mok-status.sh', dest / 'mok-status.sh')
    replacements = {'KERNEL': target['kernel'], 'OS': target['os'], 'VERSION': target['version'],
                    'LABEL': f"{target['os']} {target['release']}",
                    'MODULE_SHA256': target['module_sha256'], 'CERT_SHA256': target['certificate_sha256']}
    script = (HERE / 'install.sh.in').read_text()
    for key, value in replacements.items():
        script = script.replace('@' + key + '@', value)
    (dest / 'install.sh').write_text(script)
    if target['os'] == 'ubuntu':
        hook = (HERE.parent / 'ubuntu22-offline/initramfs-hook').read_text().replace('5.15.0-78-generic', target['kernel'])
    else:
        hook = '# E610 offline driver: retain ixgbe in generated boot images.\nadd_drivers+=" ixgbe "\n'
    (dest / 'initramfs-hook').write_text(hook)
    checksums(dest)


if __name__ == '__main__':
    stage(Path(sys.argv[1]))

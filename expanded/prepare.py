#!/usr/bin/env python3
"""Fetch verified media, inspect native aliases, and build exact-kernel modules."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess as sp
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SOURCE_SHA = '8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4'
IDS = ['57AE', '57AF', '57B0', '57B1', '57B2']


def run(*args, **kwargs):
    return sp.run([str(a) for a in args], check=True, **kwargs)


def sha(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def download(url, path, digest=None):
    run('curl', '--fail', '--location', '--retry', '4', '--connect-timeout', '30', '-o', path, url)
    if digest and sha(path) != digest:
        raise ValueError(f'Checksum mismatch: {url}')


def extract_iso(iso, source, dest):
    run('xorriso', '-osirrox', 'on', '-indev', iso, '-extract', source, dest)


def inspect_and_build(target, work, out, kernel, package_sources):
    kwork = work / kernel
    kout = out / kernel
    kout.mkdir(parents=True, exist_ok=True)
    root = kwork / 'root'
    modules = list(root.glob(f'**/modules/{kernel}/kernel/drivers/net/ethernet/intel/ixgbe/ixgbe.ko*'))
    assert len(modules) == 1, modules
    stock = modules[0]
    aliases = sp.check_output(['modinfo', '-F', 'alias', str(stock)], text=True)
    supported = [i for i in IDS if f'v00008086d0000{i}' in aliases]
    native = len(supported) == len(IDS)
    (kout / 'stock-modinfo.txt').write_text(sp.check_output(['modinfo', str(stock)], text=True))
    record = {k: target[k] for k in ('id', 'os', 'version', 'release')}
    record.update(kernel=kernel, native=native, native_pci_ids=supported,
                  source=package_sources, stock_module_sha256=sha(stock),
                  commit=os.environ['GITHUB_SHA'], run_id=os.environ['GITHUB_RUN_ID'])
    shutil.copyfile(work / 'ixgbe-6.4.5.tar.gz', kwork / 'ixgbe-6.4.5.tar.gz')
    if not native:
        if target['os'] == 'ubuntu':
            headers = kwork / 'headers/usr/src' / ('linux-headers-' + kernel)
            if not headers.exists():
                headers = root / 'usr/src' / ('linux-headers-' + kernel)
            assert headers.exists(), headers
            major, minor = map(int, kernel.split('-')[0].split('.')[:2])
            compiler = 'gcc-11' if (major, minor) <= (5, 15) else ('gcc-12' if (major, minor) <= (6, 5) else 'gcc-13')
            run('bash', HERE / 'build-driver.sh', kwork, kout, kernel, headers, compiler)
        else:
            run('docker', 'run', '--rm', '--network', 'none', '-v', f'{work}:{work}', '-v', f'{out}:{out}',
                '-v', f'{ROOT}:/repo:ro', 'e610-rocky-build', 'bash', '-c',
                'set -e; rpm -ivh --nodeps "$1"; bash /repo/expanded/build-driver.sh "$2" "$3" "$4" "/usr/src/kernels/$4"',
                'bash', next((kwork / 'rpms').glob('kernel-devel-*.rpm')), kwork, kout, kernel)
            run('sudo', 'chown', '-R', f'{os.getuid()}:{os.getgid()}', kwork, kout)
        dest = modules[0].parents[6] / 'updates/e610/ixgbe.ko'
        # Locate the actual version directory independently of usr-merge.
        version_dir = next(p for p in stock.parents if p.name == kernel)
        dest = version_dir / 'updates/e610/ixgbe.ko'
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(kout / 'ixgbe.ko', dest)
        record['module_sha256'] = sha(kout / 'ixgbe.ko')
        record['certificate_sha256'] = sha(kout / 'E610-MOK.der')
    # depmod requires /lib even if the RPM stores modules under /usr/lib.
    if not (root / 'lib').exists():
        (root / 'lib').symlink_to('usr/lib')
    run('depmod', '-b', root, '-a', kernel)
    order = sp.check_output(['modprobe', '-d', str(root), '-S', kernel, '--show-depends', 'ixgbe'], text=True)
    (kout / 'load-order.txt').write_text(order)
    (kout / 'target.json').write_text(json.dumps(record, indent=2) + '\n')
    print('E610_INVENTORY_RESULT ' + json.dumps(record), flush=True)
    run('sudo', 'bash', HERE / 'smoke.sh', kwork, kout, kernel, 'native' if native else 'external')


def main():
    target = next(t for t in json.loads(Path(sys.argv[1]).read_text()) if t['id'] == sys.argv[2])
    work, out = Path(sys.argv[3]).resolve(), Path(sys.argv[4]).resolve()
    work.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    download('https://github.com/intel/ethernet-linux-ixgbe/releases/download/v6.4.5/ixgbe-6.4.5.tar.gz', work / 'ixgbe-6.4.5.tar.gz', SOURCE_SHA)
    kernels = {}
    if target['os'] == 'ubuntu':
        iso = work / 'original.iso'
        download(target['iso_url'], iso, target['iso_sha256'])
        for entry in target['kernels']:
            kernel = entry['kernel']
            kw = work / kernel
            for name in ('root', 'headers', 'debs'):
                (kw / name).mkdir(parents=True, exist_ok=True)
            source = {'iso_url': target['iso_url'], 'iso_sha256': target['iso_sha256'], 'packages': {}}
            for path in entry['paths']:
                dest = kw / 'debs' / Path(path).name
                extract_iso(iso, path, dest)
                source['packages'][path] = sha(dest)
                run('dpkg-deb', '-x', dest, kw / ('headers' if 'headers' in dest.name else 'root'))
            kernels[kernel] = source
        # Recent server media put HWE headers and modules into a squashfs layer.
        for overlay in target.get('hwe_overlays', []):
            sq = work / 'hwe.squashfs'
            tree = work / 'hwe-root'
            extract_iso(iso, overlay, sq)
            run('unsquashfs', '-no-xattrs', '-no-progress', '-d', tree, sq)
            candidates = sorted({p.parent.name for p in tree.glob('**/modules/*/kernel')})
            for kernel in candidates:
                if kernel in kernels:
                    continue
                kw = work / kernel
                kw.mkdir(exist_ok=True)
                shutil.copytree(tree, kw / 'root', symlinks=True)
                kernels[kernel] = {'iso_url': target['iso_url'], 'iso_sha256': target['iso_sha256'], 'overlay': overlay, 'overlay_sha256': sha(sq)}
    else:
        run('docker', 'build', '--build-arg', 'MAJOR=' + target['version'], '-f', HERE / 'rocky-build.Dockerfile', '-t', 'e610-rocky-build', ROOT)
        for entry in target['kernels']:
            kernel = entry['kernel']
            kw = work / kernel
            (kw / 'rpms').mkdir(parents=True, exist_ok=True)
            (kw / 'root').mkdir(exist_ok=True)
            source = {'repository': target['repository'], 'packages': {}}
            for url in entry['urls']:
                dest = kw / 'rpms' / url.rsplit('/', 1)[1]
                download(url, dest)
                source['packages'][url] = sha(dest)
            run('docker', 'run', '--rm', '--network', 'none', '-v', f'{kw}:{kw}', 'e610-rocky-build', 'bash', '-c',
                'set -euo pipefail; rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-*; for p in "$1"/rpms/*.rpm; do rpmkeys --checksig "$p"; (cd "$1/root"; rpm2cpio "$p" | cpio -idm --quiet); done', 'bash', kw)
            run('sudo', 'chown', '-R', f'{os.getuid()}:{os.getgid()}', kw)
            kernels[kernel] = source
    for kernel, source in kernels.items():
        inspect_and_build(target, work, out, kernel, source)


if __name__ == '__main__':
    main()

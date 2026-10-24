#!/usr/bin/env python3
"""Package verified exact-ABI drivers and ISO tools, never deployment state."""
import argparse
import gzip
import hashlib
import io
import json
import pathlib
import re
import shutil
import subprocess
import tarfile

P = pathlib.Path
NAME = 'E610-ISO-Kit-6.4.5-r1'
UPSTREAM_SHA = '8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4'
PRELOAD_SHA = '94e0003aa3c2af38bef405a80a4265a68bc6ba02bb1d99b13ea8b9bc3cfc4c5e'


def sha(p):
    h = hashlib.sha256()
    with p.open('rb') as f:
        for data in iter(lambda: f.read(1048576), b''):
            h.update(data)
    return h.hexdigest()


def write(p, data, mode=0o644):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    p.chmod(mode)


def json_write(p, data):
    write(p, (json.dumps(data, indent=2, ensure_ascii=False) + '\n').encode())


def unpack_source(archive, dest):
    with tarfile.open(archive) as tar:
        for member in tar:
            path = pathlib.PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or '.git' in path.parts:
                raise ValueError('Unsafe source path: ' + member.name)
            if member.isdir():
                continue
            if not member.isfile() or path.suffix in ('.key', '.pem', '.lic', '.token'):
                raise ValueError('Unexpected source member: ' + member.name)
            write(dest / member.name, tar.extractfile(member).read(), member.mode & 0o777)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ('work', 'e610-source', 'ventoy-source', 'upstream-source', 'out'):
        ap.add_argument('--' + name, type=P, required=True)
    ap.add_argument('--source-commit', required=True)
    ap.add_argument('--ventoy-commit', required=True)
    a = ap.parse_args()
    for commit in (a.source_commit, a.ventoy_commit):
        if not re.fullmatch('[0-9a-f]{40}', commit):
            raise ValueError('A full immutable source commit is required')
    a.out.mkdir(parents=True, exist_ok=True)
    root = a.out / NAME
    root.mkdir()  # refuse to overwrite an existing release directory
    unpack_source(a.e610_source, root / 'source/E610')
    unpack_source(a.ventoy_source, root / 'source/ventoy')
    src = root / 'source/E610/pxe-media'
    catalog = json.loads((src / 'baked-catalog.json').read_text())
    evidence = json.loads((src / 'catalog-evidence.json').read_text())
    smoke = json.loads((a.work / 'kernel-smoke-results.json').read_text())
    if len(catalog['images']) != 43 or len(smoke) != 38:
        raise ValueError('Unexpected release inventory')
    if len({v['source_iso'] for v in catalog['images']}) != 43:
        raise ValueError('Duplicate image in release inventory')
    for image in catalog['images']:
        if image['software_installation'] != 'passed':
            raise ValueError('Unverified ISO: ' + image['source_iso'])
        for mode in ('manual', 'pxe'):
            if image['installation_cases'][mode]['status'] != 'passed':
                raise ValueError('Unverified installation: ' + image['source_iso'])
    verified = []
    modules = []
    for item in sorted(smoke, key=lambda x: x['kernel']):
        kernel = item['kernel']
        if not re.fullmatch('[A-Za-z0-9_.+-]+', kernel) or item['status'] != 'passed':
            raise ValueError('Unverified kernel')
        folder = a.work / 'drivers' / kernel
        module = folder / 'ixgbe.ko'
        if sha(module) != item['module_sha256']:
            raise ValueError('Module hash mismatch: ' + kernel)
        fields = subprocess.check_output(['modinfo', str(module)], text=True)
        if not re.search(r'^vermagic:\s+' + re.escape(kernel) + r'\s', fields, re.M):
            raise ValueError('Kernel ABI mismatch: ' + kernel)
        if not re.search(r'^version:\s+6\.4\.5\s*$', fields, re.M):
            raise ValueError('Driver version mismatch: ' + kernel)
        if not all('v00008086d0000' + i in fields for i in ('57AE', '57AF', '57B0', '57B1', '57B2')):
            raise ValueError('Missing E610 PCI alias: ' + kernel)
        hashes = {}
        for name in ('ixgbe.ko', 'E610-MOK.der', 'kcompat_generated_defs.h'):
            source = folder / name
            if source.is_file():
                write(root / 'work/drivers' / kernel / name, source.read_bytes())
                hashes[name] = sha(source)
        write(root / 'work/drivers' / kernel / 'SHA256SUMS',
              ''.join(h + '  ' + n + '\n' for n, h in sorted(hashes.items())).encode())
        verified.append({k: item[k] for k in ('kernel', 'iso', 'module_sha256', 'status')})
        modules.append({'kernel': kernel, 'files': hashes, 'exact_kernel_load': 'passed',
                        'physical_e610': 'not_tested'})
    json_write(root / 'work/kernel-smoke-results.json', verified)
    for source in sorted((src / 'assets').iterdir()):
        if not source.is_file():
            raise ValueError('Unexpected asset')
        installed = a.work / 'assets' / source.name
        if source.read_bytes() != installed.read_bytes().replace(b'\r\n', b'\n'):
            raise ValueError('Published hook differs from source: ' + source.name)
        write(root / 'work/assets' / source.name, source.read_bytes(), 0o755)
    preload = a.work / 'manual-common.tar.gz'
    if sha(preload) != PRELOAD_SHA or sha(a.upstream_source) != UPSTREAM_SHA:
        raise ValueError('Preload or upstream source hash mismatch')
    write(root / 'work/manual-common.tar.gz', preload.read_bytes())
    write(root / 'source/ixgbe-6.4.5.tar.gz', a.upstream_source.read_bytes())
    write(root / 'COPYING', (root / 'source/E610/COPYING').read_bytes())
    write(root / 'INSTALL.zh-CN.md', (src / 'RELEASE.zh-CN.md').read_bytes())
    for name in ('baked-catalog.json', 'catalog-evidence.json'):
        write(root / name, (src / name).read_bytes())
    manifest = {'release': NAME, 'format': 1, 'e610_source_commit': a.source_commit,
                'ventoy_source_commit': a.ventoy_commit, 'upstream_source_sha256': UPSTREAM_SHA,
                'manual_preload_sha256': PRELOAD_SHA, 'iso_count': 43,
                'exact_kernel_count': 38, 'accepted_installation_cases': 86,
                'includes_complete_os_isos': False, 'includes_installation_answers': False,
                'physical_e610': 'not_tested', 'modules': modules}
    json_write(root / 'release-manifest.json', manifest)
    rows = ['# E610 ISO Kit 镜像清单', '',
            '43 个不同原版镜像；9 个原生支持镜像保留原驱动。精确内核以模块及介质检查为准。', '',
            '| 原版 ISO | 本轮安装内核 | 手动 / PXE 软件验收 |', '| --- | --- | --- |']
    for item in catalog['images']:
        kernels = sorted({v['kernel'] for v in item['installation_cases'].values()})
        rows.append('| ' + item['source_iso'] + ' | ' + ', '.join(kernels) + ' | passed / passed |')
    rows += ['', '镜像源及成品 SHA-256、所有启动 ABI、安装入口和验证边界见 baked-catalog.json 与 catalog-evidence.json。',
             '重制成品会包含生成时间等元数据，不能把现场成品 SHA-256 直接当作每次重建的预期哈希。',
             '尚无本轮 E610 实卡链路、DHCP/收发或机器 Secure Boot 信任登记验收。', '']
    write(root / 'SUPPORTED-SYSTEMS.zh-CN.md', '\n'.join(rows).encode())
    files = sorted(p for p in root.rglob('*') if p.is_file())
    write(root / 'SHA256SUMS', ''.join(sha(p) + '  ' + p.relative_to(root).as_posix() + '\n' for p in files).encode())
    archive = a.out / (NAME + '.tar.gz')
    with archive.open('xb') as out, gzip.GzipFile(fileobj=out, mode='wb', mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode='w', format=tarfile.PAX_FORMAT) as tar:
            for p in sorted(p for p in root.rglob('*') if p.is_file()):
                data = p.read_bytes()
                info = tarfile.TarInfo(NAME + '/' + p.relative_to(root).as_posix())
                info.size = len(data)
                info.mode = p.stat().st_mode & 0o777
                tar.addfile(info, io.BytesIO(data))
    for name in ('INSTALL.zh-CN.md', 'SUPPORTED-SYSTEMS.zh-CN.md', 'release-manifest.json',
                 'baked-catalog.json', 'catalog-evidence.json'):
        shutil.copyfile(root / name, a.out / name)
    assets = sorted(p for p in a.out.iterdir() if p.is_file())
    write(a.out / 'SHA256SUMS', ''.join(sha(p) + '  ' + p.name + '\n' for p in assets).encode())
    print(json.dumps({'archive': archive.name, 'size': archive.stat().st_size, 'sha256': sha(archive),
                      'modules': len(modules), 'images': len(catalog['images']), 'files': len(files) + 1}))


if __name__ == '__main__':
    main()

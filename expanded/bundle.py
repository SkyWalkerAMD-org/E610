#!/usr/bin/env python3
"""Package only validated kernels, preserving previously released installers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess as sp
from stage import checksums

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
NAME = 'E610-MultiOS-6.4.5-r2'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def require(path, marker):
    if marker not in path.read_text():
        raise ValueError(f'Missing validation: {marker} in {path}')


def build(inputs, work, output):
    work.mkdir(parents=True, exist_ok=False)
    output.mkdir(parents=True, exist_ok=False)
    bundle = work / NAME
    (bundle / 'payloads').mkdir(parents=True)
    records, rows, known = [], [], set()
    legacy = json.loads((ROOT / 'multios/payloads.json').read_text())
    for key, value in legacy.items():
        dest = bundle / 'payloads' / value['file']
        url = f"https://github.com/SkyWalkerAMD-org/E610/releases/download/{value['release']}/{value['file']}"
        sp.run(['curl', '-fL', '--retry', '3', '-o', str(dest), url], check=True)
        assert sha(dest) == value['sha256'], key
        system, version = ('centos', '7') if key == 'centos7' else ('ubuntu', '22.04' if key == 'ubuntu22' else '24.04')
        for kernel in value['kernels']:
            known.add((system, version, kernel))
            rows.append((system, version, kernel, 'legacy', 'payloads/' + value['file']))
            records.append({'os': system, 'version': version, 'release': '7.9' if system == 'centos' else version,
                            'kernel': kernel, 'kind': 'legacy', 'original_release': value})
    inventory = json.loads((HERE / 'inventory.json').read_text())
    seen = set()
    for metadata in sorted(inputs.glob('**/target.json')):
        if metadata.parent.name == 'payload':
            continue
        item = json.loads(metadata.read_text())
        key = item['os'], item['version'], item['kernel']
        seen.add((item['id'], item['kernel']))
        if key in known:
            continue
        known.add(key)
        kind = 'native' if item['native'] else 'external'
        require(metadata.parent / 'boot.log', f"E610_KERNEL_LOAD_PASS kernel={item['kernel']} kind={kind if kind == 'native' else 'external'}")
        if not item['native']:
            require(metadata.parent / 'secure-boot.log', f"E610_SECURE_BOOT_LOAD_PASS kernel={item['kernel']}")
            require(metadata.parent / 'installer-test.log', f"E610_INSTALLER_TEST_PASS kernel={item['kernel']}")
            path = f"payloads/{item['os']}-{item['version']}-{item['kernel']}"
            shutil.copytree(metadata.parent / 'payload', bundle / path)
        else:
            path = '-'
        evidence = bundle / 'evidence' / item['id'] / item['kernel']
        evidence.mkdir(parents=True)
        for p in metadata.parent.iterdir():
            if p.is_file() and (p.suffix in ('.log', '.txt', '.json') or p.name == 'payload.sha256'):
                shutil.copyfile(p, evidence / p.name)
        rows.append((*key, kind, path))
        item['kind'] = kind
        records.append(item)
    completed_media = {json.loads(p.read_text())['id']: json.loads(p.read_text()) for p in inputs.glob('**/media-result.json')}
    for target in inventory:
        assert target['id'] in completed_media and completed_media[target['id']]['complete'], f"Incomplete media: {target['id']}"
        for kernel in completed_media[target['id']]['kernels']:
            assert (target['id'], kernel) in seen, f"Missing discovered kernel: {target['id']} {kernel}"
        for kernel in target['kernels']:
            assert (target['id'], kernel['kernel']) in seen, f"Missing {target['id']} {kernel['kernel']}"
        if target.get('hwe_overlays'):
            assert len(completed_media[target['id']]['kernels']) >= 2, f"Missing HWE: {target['id']}"
    (bundle / 'targets.tsv').write_text(''.join('\t'.join(row) + '\n' for row in rows))
    shutil.copyfile(HERE / 'dispatch.sh', bundle / 'install.sh')
    shutil.copyfile(HERE / 'INSTALL.zh-CN.md', bundle / 'INSTALL.zh-CN.md')
    shutil.copyfile(HERE / 'inventory.json', bundle / 'installation-media.json')
    (bundle / 'source').mkdir()
    source = bundle / 'source/ixgbe-6.4.5.tar.gz'
    sp.run(['curl', '-fL', '--retry', '3', '-o', str(source), 'https://github.com/intel/ethernet-linux-ixgbe/releases/download/v6.4.5/ixgbe-6.4.5.tar.gz'], check=True)
    assert sha(source) == '8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4'
    table = '# E610 多系统 r2 精确内核清单\n\n仅支持 x86_64；不升级内核。系统更新后的其他 ABI 不自动包含在此表中。\n\n'
    table += '| 系统 / 安装介质 | 内核 | 处理方式 |\n| --- | --- | --- |\n'
    labels = {'legacy': '沿用已发布的原包和备份', 'external': '离线安装 ixgbe 6.4.5', 'native': '系统原生支持，检查后无需安装'}
    for record in records:
        table += f"| {record['os']} {record['release']} | `{record['kernel']}` | {labels[record['kind']]} |\n"
    (bundle / 'SUPPORTED-SYSTEMS.zh-CN.md').write_text(table)
    manifest = {'package': NAME, 'architecture': 'x86_64', 'targets': records,
                'commit': os.environ['GITHUB_SHA'], 'run_id': os.environ['GITHUB_RUN_ID'],
                'kernel_replaced': False, 'network_required_on_target': False,
                'compiler_required_on_target': False, 'media_type': 'nonbootable driver data ISO'}
    (bundle / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    validation = ('# 云端验证记录\n\n'
        f"构建提交：`{os.environ['GITHUB_SHA']}`。\n\n"
        f"[打包与介质测试](https://github.com/SkyWalkerAMD-org/E610/actions/runs/{os.environ['GITHUB_RUN_ID']})。\n\n"
        '逐内核测试运行：' + '、'.join(f"[{run}](https://github.com/SkyWalkerAMD-org/E610/actions/runs/{run})" for run in sorted({r['run_id'] for r in records if 'run_id' in r})) + '。\n\n'
        '新增外部模块：精确内核编译、全部五个 E610 PCI 设备 ID、真实内核三次加载卸载；UEFI Secure Boot 下已注册 MOK 的模块加载、未签名模块拒绝；断网、无编译器环境的安装、重复安装、原文件保留、损坏备份拒绝、启动镜像失败恢复及回退。\n\n'
        '原生支持组合：直接检查官方介质中的 ixgbe 模块 PCI 别名，并启动对应内核验证三次加载卸载。无额外驱动写入。\n\n'
        'Secure Boot 测试预先导入测试所需公钥；Rocky 和 Ubuntu 22.04 初版旧内核使用测试用 Ubuntu shim，附加信任原内核的供应商公钥，未修改或重新签名原内核。不能替代现场固件 MOK 交互验证，也不表示任意新版启动链默认接受旧内核。\n\n'
        '安装回退使用相同发行版大版本的容器用户空间：Ubuntu 22.04 / 24.04、Rocky 8 / 9 当前仓库；逐一放入精确的旧内核模块和配置。没有逐个重装每张历史系统镜像。\n\n'
        '原有 CentOS 7.9、Ubuntu 22.04.3 GA、Ubuntu 24.04 初始 GA 保持原始发布包字节和证书不变，其原始测试记录见 manifest.json。\n\n'
        '虚拟机没有 E610 实卡。本次新增系统未进行实机链路、吞吐、PTP、SR-IOV 和长期稳定性测试。\n')
    (bundle / 'VALIDATION.zh-CN.md').write_text(validation)
    checksums(bundle)
    archive = output / (NAME + '.tar.gz')
    sp.run(['tar', '--owner=0', '--group=0', '--numeric-owner', '-czf', str(archive), '-C', str(work), NAME], check=True)
    header = (ROOT / 'multios/launcher.sh.in').read_text().replace('6.4.5-r1', '6.4.5-r2')
    start = header.index("    echo '自动识别系统")
    end = header.index('    exit 0', start)
    header = header[:start] + "    cat <<'E610_SUPPORTED_MATRIX'\n" + table + 'E610_SUPPORTED_MATRIX\n' + header[end:]
    header = header.replace('@ARCHIVE_SHA256@', sha(archive))
    header = header.replace('@PAYLOAD_LINE@', str(header.count('\n') + 1))
    installer = output / (NAME + '.run')
    installer.write_bytes(header.encode() + archive.read_bytes())
    installer.chmod(0o755)
    media = work / 'iso-root'
    media.mkdir()
    shutil.copyfile(installer, media / installer.name)
    (media / 'install.sh').write_text('#!/bin/bash\nset -e\nhere=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)\nexec bash "$here/' + NAME + '.run" "$@"\n')
    for name in ('INSTALL.zh-CN.md', 'SUPPORTED-SYSTEMS.zh-CN.md', 'VALIDATION.zh-CN.md', 'manifest.json'):
        shutil.copyfile(bundle / name, media / name)
        shutil.copyfile(bundle / name, output / name)
    checksums(media)
    sp.run(['xorriso', '-as', 'mkisofs', '-iso-level', '3', '-r', '-J', '-joliet-long', '-V', 'E610_MULTIOS', '-o', str(output / (NAME + '.iso')), str(media)], check=True)
    checksums(output)
    print(f'E610_EXPANDED_BUNDLE_PASS targets={len(records)}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ('inputs', 'work', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    build(args.inputs.resolve(), args.work.resolve(), args.output.resolve())

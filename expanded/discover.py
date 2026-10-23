#!/usr/bin/env python3
"""Inventory the GA/HWE packages on official x86_64 installation media."""
import concurrent.futures
import json
from pathlib import Path
import re
import urllib.request


def get(url):
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read().decode()


def ubuntu(version):
    name = f"ubuntu-{version}-live-server-amd64"
    errors = []
    for base in (f"https://releases.ubuntu.com/{version}/", f"https://old-releases.ubuntu.com/releases/{version}/"):
        try:
            sums = get(base + "SHA256SUMS")
            digest = next(line.split()[0] for line in sums.splitlines() if line.split()[-1].lstrip('*') == name + '.iso')
            listing = get(base + name + '.list').splitlines()
            kernels = []
            for path in listing:
                match = re.search(r'/linux-image-(\d[^_]*-generic)_', path)
                if not match:
                    continue
                kernel = match[1]
                abi = kernel.removesuffix('-generic')
                paths = [p for p in listing if p.endswith('.deb') and (
                    re.search(r'/linux-(?:image|modules|modules-extra|headers)-' + re.escape(kernel) + '_', p)
                    or re.search(r'/linux-(?:hwe-[\d.]+-)?headers-' + re.escape(abi) + '_', p))]
                assert len(paths) == 5, (kernel, paths)
                kernels.append({'kernel': kernel, 'paths': paths})
            assert kernels
            return {'id': 'ubuntu-' + version, 'os': 'ubuntu', 'version': version[:5],
                    'release': version, 'iso_url': base + name + '.iso', 'iso_sha256': digest,
                    'kernels': kernels}
        except Exception as exc:
            errors.append(str(exc))
    raise RuntimeError(f'Ubuntu {version}: {errors}')


def rocky(version):
    errors = []
    for base in (f'https://dl.rockylinux.org/pub/rocky/{version}/', f'https://dl.rockylinux.org/vault/rocky/{version}/'):
        try:
            core_dir = base + 'BaseOS/x86_64/kickstart/Packages/k/'
            listing = get(core_dir)
            kernels = sorted(set(re.findall(r'href="kernel-core-([^"/]+\.x86_64)\.rpm"', listing)))
            assert len(kernels) == 1, kernels
            kernel = kernels[0]
            devel_dir = base + 'AppStream/x86_64/kickstart/Packages/k/'
            devlisting = get(devel_dir)
            assert f'kernel-devel-{kernel}.rpm' in devlisting
            urls = [core_dir + f'{p}-{kernel}.rpm' for p in ('kernel-core', 'kernel-modules')]
            if f'kernel-modules-core-{kernel}.rpm' in listing:
                urls.append(core_dir + f'kernel-modules-core-{kernel}.rpm')
            urls.append(devel_dir + f'kernel-devel-{kernel}.rpm')
            return {'id': 'rocky-' + version, 'os': 'rocky', 'version': version.split('.')[0],
                    'release': version, 'repository': base, 'kernels': [{'kernel': kernel, 'urls': urls}]}
        except Exception as exc:
            errors.append(str(exc))
    raise RuntimeError(f'Rocky {version}: {errors}')


def main():
    tasks = [(ubuntu, f'{major}.04' + (f'.{minor}' if minor else '')) for major in (22, 24) for minor in range(6)]
    tasks += [(rocky, f'8.{minor}') for minor in range(4, 11)]
    tasks += [(rocky, f'9.{minor}') for minor in range(9)]
    targets, failures = [], []
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        futures = {pool.submit(fn, version): version for fn, version in tasks}
        for future in concurrent.futures.as_completed(futures):
            try:
                result = future.result()
                targets.append(result)
                print(json.dumps(result), flush=True)
            except Exception as exc:
                failures.append(str(exc))
                print(str(exc), flush=True)
    targets.sort(key=lambda t: t['id'])
    Path('output').mkdir(exist_ok=True)
    Path('output/inventory.json').write_text(json.dumps(targets, indent=2) + '\n')
    Path('output/discovery-errors.json').write_text(json.dumps(failures, indent=2) + '\n')
    if failures:
        raise SystemExit('Some official media need investigation; see discovery-errors.json')


if __name__ == '__main__':
    main()

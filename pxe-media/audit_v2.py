#!/usr/bin/env python3
"""Audit every boot ABI, including Debian installer udebs and multi-CPIO Ubuntu."""
import concurrent.futures
import hashlib
import importlib.util
import json
import pathlib
import re
import subprocess
import sys

P = pathlib.Path
spec = importlib.util.spec_from_file_location('media', P(__file__).with_name('media_lib.py'))
media = importlib.util.module_from_spec(spec); spec.loader.exec_module(media)
IDS = ('57AE','57AF','57B0','57B1','57B2')


def run(args, **kw):
    return subprocess.run([str(a) for a in args], check=True, **kw)


def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024), b''): h.update(block)
    return h.hexdigest()


def info(dest, source):
    text=run(['modinfo', dest], capture_output=True, text=True).stdout
    fields={}
    for line in text.splitlines():
        if ':' in line:
            k,v=line.split(':',1); fields.setdefault(k,[]).append(v.strip())
    ids=[i for i in IDS if any('v00008086d0000'+i in a for a in fields.get('alias',[]))]
    return dict(path=source, file=str(dest), kernel=fields['vermagic'][0].split()[0],
                pci_ids=ids, all_e610_ids=len(ids)==5, version=fields.get('version',[''])[0], sha256=sha(dest))


def inspect(record, iso_root):
    folder=P(record['work']); iso=iso_root/record['iso']
    paths=[s.strip().strip("'") for s in (folder/'iso-files.txt').read_text().splitlines()]
    for index,boot in enumerate(record['boots']):
        modules=[]; kernels=set(); root=folder/('boot-files-'+str(index));root.mkdir(exist_ok=True)
        for name,mode,data in media.initramfs_files((folder/('initrd-'+str(index))).read_bytes()):
            match=re.search(r'(?:^|/)lib/modules/([^/]+)/',name)
            if match:kernels.add(match[1])
            # Keep the stock module tree for later exact-kernel load tests.
            if (mode & 0o170000)==0o100000 and (match or name=='init'):
                dest=media.file_path(root,name);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
                if re.search(r'/ixgbe\.ko(?:\.(?:xz|gz|zst))?$',name):modules.append(info(dest,name))
        if record['iso'].startswith('Debian/'):
            packages=[x for x in paths if P(x).name.startswith('nic-modules-') and x.endswith('.udeb')]
            for path in packages:
                dest=folder/P(path).name
                if not dest.exists():run(['xorriso','-osirrox','on','-indev',iso,'-extract',path,dest],capture_output=True)
                for name,data in media.deb_files(dest):
                    target=media.file_path(root,name);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
                    if re.search(r'/ixgbe\.ko(?:\.(?:xz|gz|zst))?$',name):modules.append(info(target,path+':'+name))
        boot['modules']=modules;boot['detected_kernels']=sorted(kernels)
        boot['error']='ixgbe missing; must inspect installed-module package' if not modules else ''
    native=all(b['modules'] and all(m['all_e610_ids'] for m in b['modules']) for b in record['boots'])
    record['status']='existing-adapted' if 'E610' in iso.name else ('boot-native' if native else 'needs-injection')
    record['audit_version']=2
    (folder/'audit-v2.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps({'iso':record['iso'],'status':record['status'],'kernels':[(m['kernel'],m['pci_ids']) for b in record['boots'] for m in b['modules']]}),flush=True)
    return record


def main():
    inventory=P(sys.argv[1]);iso_root=P(sys.argv[2]);records=json.loads(inventory.read_text())
    def safe(r):
        try:return inspect(r,iso_root)
        except Exception as e:
            r['status']='audit-error';r['error']=repr(e);print('ERROR',r['iso'],repr(e),flush=True);return r
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:out=list(pool.map(safe,records))
    inventory.with_name('inventory-v2.json').write_text(json.dumps(out,indent=2)+'\n')
    print('SUMMARY',json.dumps({k:sum(r['status']==k for r in out) for k in sorted({r['status'] for r in out})}),flush=True)


if __name__=='__main__':main()

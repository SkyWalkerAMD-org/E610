#!/usr/bin/env python3
"""Audit installed-media E610 PCI aliases without changing original ISO files."""
import argparse,hashlib,json,pathlib,re,subprocess,concurrent.futures
from audit_v2 import inspect as inspect_boots
P=pathlib.Path
IDS=('57AE','57AF','57B0','57B1','57B2')
def run(args,**kw):
    return subprocess.run([str(x) for x in args],check=True,**kw)
def sha(p):
    d=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):d.update(b)
    return d.hexdigest()
def inspect(iso,root,work):
    name=str(iso.relative_to(root)); folder=work/('image-'+hashlib.sha256(name.encode()).hexdigest()[:12])
    folder.mkdir(exist_ok=True)
    result={'iso':name,'size':iso.stat().st_size,'work':str(folder),'boots':[]}
    try:
        listing=run(['xorriso','-indev',iso,'-find','/','-type','f','-exec','echo','--'],capture_output=True,text=True).stdout
        (folder/'iso-files.txt').write_text(listing)
        paths=[s.strip().strip("'") for s in listing.splitlines() if s.strip().startswith(("'/",'/'))]
        if iso.parent.name=='Ubuntu':
            variants=[(p,p.rsplit('/',1)[0]+'/'+('hwe-vmlinuz' if 'hwe-initrd' in p else 'vmlinuz')) for p in paths if re.fullmatch('/casper/(hwe-)?initrd',p)]
        elif iso.parent.name=='Debian':
            variants=[(p,'/install.amd/vmlinuz') for p in ('/install.amd/initrd.gz','/install.amd/gtk/initrd.gz') if p in paths]
        else:variants=[('/images/pxeboot/initrd.img','/images/pxeboot/vmlinuz')]
        if not variants:raise RuntimeError('No supported boot initrd')
        for index,(initrdpath,kernelpath) in enumerate(variants):
            initrd=folder/('initrd-'+str(index));kernel=folder/('vmlinuz-'+str(index))
            if not initrd.exists():
                run(['xorriso','-osirrox','on','-indev',iso,'-extract',initrdpath,initrd,'-extract',kernelpath,kernel],capture_output=True)
            boot={'initrd':initrdpath,'kernel_path':kernelpath,'initrd_sha256':sha(initrd),'kernel_sha256':sha(kernel),'modules':[]}
            result['boots'].append(boot)
        result=inspect_boots(result,root)
    except Exception as exc:result.update(status='audit-error',error=str(exc))
    (folder/'audit.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'iso':name,'status':result['status'],'kernels':[(m['kernel'],m['pci_ids']) for b in result['boots'] for m in b['modules']],'error':result.get('error','')}),flush=True)
    return result
def main():
    p=argparse.ArgumentParser();p.add_argument('--iso-root',type=P,required=True);p.add_argument('--work',type=P,required=True);a=p.parse_args()
    root=a.iso_root.resolve();work=a.work.resolve();assert not work.is_relative_to(root)
    work.mkdir(mode=0o700,parents=True,exist_ok=True)
    isos=[f for f in sorted(root.glob('*/*.iso')) if f.parent.name in ('AlmaLinux','CentOS','Debian','RHEL','Rocky','Ubuntu')]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(lambda f:inspect(f,root,work),isos))
    (work/'inventory.json').write_text(json.dumps(results,indent=2)+'\n')
    (work/'inventory-v2.json').write_text(json.dumps(results,indent=2)+'\n')
    print('SUMMARY',json.dumps({k:sum(r['status']==k for r in results) for k in sorted({r['status'] for r in results})}),flush=True)
if __name__=='__main__':main()


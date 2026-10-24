#!/usr/bin/env python3
"""Assemble an exact-ABI initramfs overlay; original ISO and kernels stay intact."""
import argparse, gzip, hashlib, io, json, pathlib, re, shutil, subprocess, tarfile
P=pathlib.Path
IDS=('57AE','57AF','57B0','57B1','57B2')
def run(args,**kw):return subprocess.run([str(x) for x in args],check=True,**kw)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def cpio(files):
    out=bytearray()
    for index,(name,data,mode) in enumerate(files+[('TRAILER!!!',b'',0)]):
        b=name.encode()+b'\0'
        out+=b'070701'+''.join('%08x'%v for v in (index,mode,0,0,1,0,len(data),0,0,0,0,len(b),0)).encode()+b
        out+=b'\0'*((-len(out))%4);out+=data;out+=b'\0'*((-len(out))%4)
    return gzip.compress(bytes(out),mtime=0)

def prepare(record,index,work):
    boot=record['boots'][index]
    missing=[m for m in boot['modules'] if not m['all_e610_ids']]
    if not missing:return None
    kernels={m['kernel'] for m in missing};assert len(kernels)==1,kernels
    k=next(iter(kernels));source=work/'drivers'/k/'ixgbe.ko'
    if not source.is_file():raise ValueError('Module not yet built: '+k)
    fields=run(['modinfo',source],capture_output=True,text=True).stdout
    assert re.search(r'^vermagic:\s+'+re.escape(k)+r'\s',fields,re.M)
    assert all('v00008086d0000'+i in fields for i in IDS)
    folder=P(record['work'])/('overlay-'+str(index));folder.mkdir(exist_ok=True)
    root=folder/'root'
    if not root.exists():shutil.copytree(P(record['work'])/('boot-files-'+str(index)),root)
    # Debian text and GTK installers share an ABI but carry different modules.
    # Use one union index so a single payload supports both native boot paths.
    if record['iso'].startswith('Debian/'):
        for i in range(len(record['boots'])):
            other=P(record['work'])/('boot-files-'+str(i))
            for module in other.rglob('*'):
                if module.is_file() and '.ko' in module.name:
                    dest=root/module.relative_to(other);dest.parent.mkdir(parents=True,exist_ok=True)
                    if dest.exists():assert sha(dest)==sha(module),str(dest)
                    else:shutil.copyfile(module,dest)
    if (root/'usr/lib/modules').is_dir() and not (root/'lib').exists():(root/'lib').symlink_to('usr/lib')
    base=root/'lib/modules'/k
    override=base/'updates/e610/ixgbe.ko';override.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,override)
    # Keep the original boot tree for dependency resolution; ship only override
    # and depmod indexes. Debian's NIC udebs are materialized in the audited tree.
    run(['depmod','-b',root,k],capture_output=True)
    order=run(['modprobe','-d',root,'-S',k,'--show-depends','ixgbe'],capture_output=True,text=True).stdout
    assert '/updates/e610/ixgbe.ko' in order,order
    (folder/'load-order.txt').write_text(order)
    files={}
    def add(path):
        actual=path.resolve();rel=actual.relative_to(root.resolve()).as_posix()
        files[rel]=(actual.read_bytes(),0o644)
    add(override)
    for f in base.glob('modules.*'):
        if f.is_file():add(f)
    # d-i loads NIC modules from the CD later, but iVentoy needs E610 networking
    # before that. Include each original-kernel dependency in the overlay too.
    for line in order.splitlines():
        if line.startswith('insmod '):add(P(line.split()[1]))
    result={'kernel':k,'module_sha256':sha(source),'initrd_index':index,'folder':str(folder),'files':files,'order':order}
    return result

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--work',type=P,required=True);a=ap.parse_args();work=a.work.resolve()
    inventory=json.loads((work/'audit/inventory-v2.json').read_text());results=[]
    for record in inventory:
        if record['status'] in ('existing-adapted','boot-native'):continue
        item={'iso':record['iso'],'boots':[]}
        try:
            combined={}
            for i in range(len(record['boots'])):
                result=prepare(record,i,work)
                if not result:continue
                files=result.pop('files')
                for name,value in files.items():
                    if name in combined:assert combined[name]==value,name
                    combined[name]=value
                item['boots'].append(result)
            folder=P(record['work']);archive=folder/'driver-boot.tar.gz'
            with archive.open('wb') as f:
                with gzip.GzipFile(fileobj=f,mode='wb',mtime=0) as gz:
                    with tarfile.open(fileobj=gz,mode='w') as tar:
                        for name,(data,mode) in sorted(combined.items()):
                            h=tarfile.TarInfo(name);h.size=len(data);h.mode=mode;tar.addfile(h,io.BytesIO(data))
            item.update(status='assembled',archive=str(archive),sha256=sha(archive))
        except Exception as e:item.update(status='pending',error=repr(e))
        results.append(item);print(item['iso'],item['status'],item.get('error',''),flush=True)
    (work/'boot-overlays.json').write_text(json.dumps(results,indent=2)+'\n')

if __name__=='__main__':main()

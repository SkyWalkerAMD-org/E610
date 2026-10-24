#!/usr/bin/env python3
"""Embed exact-kernel drivers and completion hooks inside a bootable ISO.

The original ISO is never opened for writing. Reflink plus xorriso growing
shares unchanged data, while the resulting ISO remains a standalone file.
"""
import argparse, gzip, hashlib, io, json, os, pathlib, re, shutil, subprocess, tarfile
from media_lib import initramfs_files, normalize_for_append, rewrite_initramfs_files
from assemble_boot import cpio, prepare
P=pathlib.Path
HOOK='live_injection_7ed136ec_7a61_4b54_adc3_ae494d5106ea/hook.sh'

def run(args,**kw):return subprocess.run([str(x) for x in args],check=True,**kw)
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(4*1024*1024),b''):h.update(b)
    return h.hexdigest()
def archive_files(p):
    files={}
    with tarfile.open(p) as tar:
        for m in tar:
            assert m.isfile() and not m.name.startswith('/') and '..' not in P(m.name).parts
            if m.name==HOOK:continue # Native /init and dracut hooks are embedded below.
            files[m.name]=(tar.extractfile(m).read(),0o100000|m.mode)
    return files

def embed_initrd(raw, files, ubuntu):
    existing={};order=None
    for n,m,d in initramfs_files(raw):
        existing[n]=m
        if n=='scripts/init-bottom/ORDER':order=d
    payload=dict(files)
    if ubuntu:
        assert order is not None and 'ventoy-e610/ubuntu-stage.sh' in payload
        # iVentoy replaces /init. Use the native init-bottom sequence and edit
        # its original CPIO record, so first-entry archive readers also see it.
        order += b'\nif ! /bin/sh /ventoy-e610/ubuntu-stage.sh "$rootmnt"; then\n    panic "E610 installer preparation failed"\n    exit 1\nfi\n'
        raw=rewrite_initramfs_files(raw,{'scripts/init-bottom/ORDER':order})
    dirs=set()
    for name in payload:
        for p in P(name).parents:
            if str(p)!='.' and str(p) not in existing:dirs.add(str(p))
    entries=[(n,b'',0o40755) for n in sorted(dirs,key=lambda n:(n.count('/'),n))]
    entries += [(n,d,m) for n,(d,m) in sorted(payload.items())]
    return normalize_for_append(raw)+cpio(entries)

def main():
    p=argparse.ArgumentParser();p.add_argument('--work',type=P,required=True);p.add_argument('--iso-root',type=P,required=True);p.add_argument('--iso',required=True);p.add_argument('--out',type=P,required=True);a=p.parse_args()
    records=json.loads((a.work/'audit/inventory-v2.json').read_text());rec=next(v for v in records if v['iso']==a.iso)
    assert rec['status']=='needs-injection'
    manifest=json.loads((a.work/'media/manifest.json').read_text());item=manifest['images'][a.iso]
    source=(a.iso_root/a.iso).resolve();assert source.is_relative_to(a.iso_root.resolve())
    assert source.stat().st_size==item['iso_size'] and source.stat().st_mtime_ns==item['iso_mtime_ns']
    assert not a.out.exists() and a.out.suffix=='.iso';a.out.parent.mkdir(parents=True,exist_ok=True)
    folder=a.work/'baked-work'/hashlib.sha256(a.iso.encode()).hexdigest()[:12];folder.mkdir(parents=True,exist_ok=True)
    files=archive_files(a.work/'manual-common.tar.gz')
    for n,v in archive_files(a.work/'media'/item['archive']).items():
        assert n not in files or files[n]==v,n
        files[n]=v
    if a.iso.startswith('Ubuntu/'):
        files['ventoy-e610/ubuntu-stage.sh']=((a.work/'assets/ubuntu-stage.sh').read_bytes(),0o100755)
    updates={}
    for index,boot in enumerate(rec['boots']):
        raw=(P(rec['work'])/('initrd-'+str(index))).read_bytes()
        payload=files
        if a.iso.startswith('Debian/'):
            # Text and GTK boot images have distinct display-module sets.
            # A combined depmod index advertises modules absent from that image.
            payload={n:v for n,v in files.items() if not re.search(r'(?:^|/)lib/modules/',n)}
            native=prepare(rec,index,a.work,per_boot=True)
            if native:
                for n,(data,mode) in native['files'].items():payload[n]=(data,0o100000|mode)
        dest=folder/('initrd-'+str(index));dest.write_bytes(embed_initrd(raw,payload,a.iso.startswith('Ubuntu/')))
        updates[boot['initrd']]=dest
        kernel=folder/('vmlinuz-'+str(index))
        if not kernel.exists():kernel.symlink_to(P(rec['work'])/('vmlinuz-'+str(index)))
    # Legacy BIOS EL menus use the second copy under isolinux.
    paths=[s.strip().strip("'") for s in (P(rec['work'])/'iso-files.txt').read_text().splitlines()]
    if '/isolinux/initrd.img' in paths:updates['/isolinux/initrd.img']=updates['/images/pxeboot/initrd.img']
    evidence={'format':1,'source_iso':a.iso,'source_size':source.stat().st_size,'source_sha256':sha(source),'embedded_in_iso':True,'kernel_replaced':False,'hardware_e610':'not_tested','installer_paths':list(updates),'driver_archive_sha256':item['sha256']}
    evidence['manual_preload_sha256']=sha(a.work/'manual-common.tar.gz')
    if a.iso.startswith('Debian/'):evidence['boot_module_layout']='per-initrd'
    if a.iso.startswith('Ubuntu/'):evidence['live_hook']='native-init-bottom-order-v3'
    for path in ('/md5sum.txt','/SHA256SUMS','/SHA512SUMS'):
        if path not in paths:continue
        old=folder/P(path).name
        run(['xorriso','-osirrox','on','-indev',source,'-extract',path,old],capture_output=True)
        algo={'/md5sum.txt':'md5','/SHA256SUMS':'sha256','/SHA512SUMS':'sha512'}[path];lines=[]
        for line in old.read_text().splitlines():
            fields=line.split(maxsplit=1)
            if len(fields)!=2:lines.append(line);continue
            target='/'+fields[1].lstrip('*').removeprefix('./')
            if target in updates:
                fields[0]=hashlib.new(algo,updates[target].read_bytes()).hexdigest();line=fields[0]+'  '+fields[1]
            lines.append(line)
        old.write_text('\n'.join(lines)+'\n');updates[path]=old
    if '/.treeinfo' in paths:
        tree=folder/'treeinfo'
        run(['xorriso','-osirrox','on','-indev',source,'-extract','/.treeinfo',tree],capture_output=True)
        section='';lines=[]
        for line in tree.read_text().splitlines():
            if line.strip().startswith('['):section=line.strip()
            match=re.match(r'^(\s*([^=]+?)\s*=\s*)([a-z0-9]+):[a-fA-F0-9]+\s*$',line)
            if section=='[checksums]' and match:
                target='/'+match[2].strip().lstrip('/')
                if target in updates:
                    line=match[1]+match[3]+':'+hashlib.new(match[3],updates[target].read_bytes()).hexdigest()
            lines.append(line)
        tree.write_text('\n'.join(lines)+'\n');updates['/.treeinfo']=tree
    info=folder/'E610-MEDIA.json';info.write_text(json.dumps(evidence,indent=2)+'\n');updates['/E610-MEDIA.json']=info
    # Reflink is required: never silently allocate a second full ISO inventory.
    run(['cp','--reflink=always','--no-clobber',source,a.out])
    assert a.out.stat().st_ino != source.stat().st_ino
    args=['xorriso','-abort_on','FAILURE','-dev',a.out]
    for path,file in updates.items():args += ['-map',file,path]
    args += ['-boot_image','any','replay','-commit','-end']
    try:
        with (folder/'build.log').open('wb') as log:run(args,stdout=log,stderr=log)
        evidence['storage_mode']='reflink-grow'
    except subprocess.CalledProcessError:
        detail=(folder/'build.log').read_text(errors='replace')
        if 'Overlapping GPT entries requested' not in detail:raise
        # EL10 uses a hidden appended EFI partition. A growing session can
        # overlap its old GPT extent; rebuild its layout from the original.
        # This needs real space rather than reflink sharing.
        needed=source.stat().st_size+sum(p.stat().st_size for p in updates.values())
        assert shutil.disk_usage(a.out.parent).free>needed+8*1024**3,'Insufficient space for appended-EFI rewrite'
        a.out.rename(folder/'failed-grow.iso')
        evidence['storage_mode']='full-rewrite-appended-efi'
        info.write_text(json.dumps(evidence,indent=2)+'\n')
        args=['xorriso','-abort_on','FAILURE','-indev',source,'-outdev',a.out]
        for path,file in updates.items():args+=['-map',file,path]
        args+=['-boot_image','any','replay','-commit','-end']
        with (folder/'build-rewrite.log').open('wb') as log:run(args,stdout=log,stderr=log)
    # EL's menu media check uses the embedded ISO digest, separate from treeinfo.
    if '/.treeinfo' in paths:
        with (folder/'media-check.log').open('wb') as log:
            run(['implantisomd5','--force','--supported-iso',a.out],stdout=log,stderr=log)
            run(['checkisomd5',a.out],stdout=log,stderr=log)
        evidence['embedded_media_check']='passed'
    for index,boot in enumerate(rec['boots']):
        check=folder/('readback-'+str(index))
        run(['xorriso','-osirrox','on','-indev',a.out,'-extract',boot['initrd'],check],capture_output=True)
        assert sha(check)==sha(updates[boot['initrd']])
    report=run(['xorriso','-indev',a.out,'-report_el_torito','plain','-report_system_area','plain'],capture_output=True,text=True)
    (folder/'boot-report.txt').write_text(report.stdout+report.stderr)
    evidence.update(output=str(a.out),output_sha256=sha(a.out),status='built-not-installed')
    (folder/'result.json').write_text(json.dumps(evidence,indent=2)+'\n')
    rec.update(source_iso=a.iso,iso=P(a.iso).parent.as_posix()+'/'+a.out.name,work=str(folder),baked=True)
    (folder/'qa-record.json').write_text(json.dumps(rec,indent=2)+'\n')
    print('E610_ISO_BUILD_PASS',a.iso,str(a.out),flush=True)

if __name__=='__main__':main()

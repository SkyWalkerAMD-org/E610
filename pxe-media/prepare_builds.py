#!/usr/bin/env python3
"""Stage exact ISO header packages and reuse only exact-kernel published modules."""
import argparse, concurrent.futures, hashlib, io, json, pathlib, re, shutil, subprocess, tarfile
P=pathlib.Path

def run(args, **kw):return subprocess.run([str(x) for x in args],check=True,**kw)
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--work',type=P,required=True);ap.add_argument('--iso-root',type=P,required=True);ap.add_argument('--published',type=P,required=True)
    a=ap.parse_args();work=a.work.resolve();published=a.published.resolve()
    inventory=json.loads((work/'audit/inventory-v2.json').read_text());jobs={};modules={}
    source=next((published/'source').glob('*.tar.gz'))
    assert sha(source)=='8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4'
    for p in published.glob('payloads/*/ixgbe.ko'):
        k=run(['modinfo','-F','vermagic',p],capture_output=True,text=True).stdout.split()[0];modules[k]=p
    legacy=work/'legacy-modules';legacy.mkdir(exist_ok=True)
    for p in published.glob('payloads/*.run'):
        data=p.read_bytes().split(b'\n__E610_PAYLOAD_BELOW__\n',1)[1]
        with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as tar:
            for m in tar:
                if m.isfile() and m.name.endswith('/ixgbe.ko'):
                    temp=legacy/(hashlib.sha256(m.name.encode()).hexdigest()[:16]+'.ko');temp.write_bytes(tar.extractfile(m).read())
                    k=run(['modinfo','-F','vermagic',temp],capture_output=True,text=True).stdout.split()[0];modules[k]=temp
    for record in inventory:
        for index,boot in enumerate(record['boots']):
            for mod in boot['modules']:
                if mod['all_e610_ids']:continue
                k=mod['kernel']
                if k not in jobs:
                    jobs[k]={'kernel':k,'iso':record['iso'],'audit_work':record['work'],'boot_index':index,'images':[],'published_module':str(modules.get(k,''))}
                if record['iso'] not in jobs[k]['images']:jobs[k]['images'].append(record['iso'])
    def stage(job):
        k=job['kernel'];out=work/'drivers'/k;out.mkdir(parents=True,exist_ok=True)
        if job['published_module']:
            shutil.copyfile(job['published_module'],out/'ixgbe.ko');job['status']='reused-exact-kernel'
            job['module_sha256']=sha(out/'ixgbe.ko')
            # Reuse the public enrollment certificate together with its module.
            cert=P(job['published_module']).parent/'E610-MOK.der'
            if cert.is_file():shutil.copyfile(cert,out/'E610-MOK.der')
        else:
            src=P(job['audit_work']);paths=[s.strip().strip("'") for s in (src/'iso-files.txt').read_text().splitlines()]
            if '.el' in k:
                packages=[s for s in paths if P(s).name=='kernel-devel-'+k+'.rpm']
                job['builder']='c7' if '.el7' in k else ('r8' if '.el8' in k else ('d13' if '.el10' in k else 'u24'))
                job['compiler']='gcc-11' if '.el9' in k else 'gcc'
                job['headers']='/usr/src/kernels/'+k
            else:
                base=re.sub(r'-(?:generic|amd64)$','',k)
                if '+deb13-' in k:base=k.replace('-amd64','')
                packages=[s for s in paths if s.endswith('.deb') and 'headers' in P(s).name and base in P(s).name]
                if '-amd64' in k:
                    major='.'.join(k.split('.')[:2])
                    prefixes=('linux-kbuild-'+major+'_','linux-kbuild-'+k.removesuffix('-amd64')+'_')
                    packages += [s for s in paths if P(s).name.startswith(prefixes) and s.endswith('.deb')]
                job['builder']='d13' if '+deb13' in k else ('r8' if k.startswith('4.19.') else 'u24')
                job['compiler']='gcc' if job['builder']!='u24' else ('gcc-14' if k.startswith('6.11.') else ('gcc-12' if k.startswith('6.1.') else 'gcc-11'))
                job['headers']='/usr/src/linux-headers-'+k
            inputs=work/'build-inputs'/k;inputs.mkdir(parents=True,exist_ok=True)
            hashes={}
            for path in sorted(set(packages)):
                dest=inputs/P(path).name
                if not dest.exists():run(['xorriso','-osirrox','on','-indev',a.iso_root/job['iso'],'-extract',path,dest],capture_output=True)
                hashes[path]=sha(dest)
            # Oracular media omits these exact headers. Use the Ubuntu archive,
            # never headers for a newer ABI. Record source URLs and content hashes.
            if k=='6.11.0-8-generic' and not packages:
                names=['linux-headers-6.11.0-8_6.11.0-8.8_all.deb',
                       'linux-headers-6.11.0-8-generic_6.11.0-8.8_amd64.deb']
                for name in names:
                    url='https://old-releases.ubuntu.com/ubuntu/pool/main/l/linux/'+name
                    dest=inputs/name
                    if not dest.exists():run(['curl','--fail','--location','--retry','3','--output',dest,url])
                    hashes[url]=sha(dest)
            shutil.copyfile(source,inputs/'ixgbe-6.4.5.tar.gz')
            patches=inputs/'patches';patches.mkdir(exist_ok=True)
            here=P(__file__).resolve().parent
            for patch in list((here.parent/'patches').glob('*.patch'))+list(here.glob('*.patch')):
                shutil.copyfile(patch,patches/patch.name)
            job['packages']=hashes;job['status']='headers-staged' if hashes else 'headers-missing'
            job['input_dir']=str(inputs)
        (out/'build-plan.json').write_text(json.dumps(job,indent=2)+'\n')
        print(k,job['status'],flush=True)
        return job
    with concurrent.futures.ThreadPoolExecutor(3) as pool:result=list(pool.map(stage,jobs.values()))
    (work/'build-plan.json').write_text(json.dumps(result,indent=2)+'\n')

if __name__=='__main__':main()

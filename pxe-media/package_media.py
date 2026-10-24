#!/usr/bin/env python3
"""Package only modules with exact-kernel load evidence, for original ISO paths."""
import argparse, gzip, hashlib, io, json, pathlib, tarfile
P=pathlib.Path
HOOK='live_injection_7ed136ec_7a61_4b54_adc3_ae494d5106ea/hook.sh'

def digest(data):return hashlib.sha256(data).hexdigest()

def main():
    p=argparse.ArgumentParser();p.add_argument('--work',type=P,required=True);p.add_argument('--iso-root',type=P,required=True);p.add_argument('--out',type=P,required=True);a=p.parse_args()
    a.out.mkdir(parents=True,exist_ok=True)
    tests={v['kernel']:v for v in json.loads((a.work/'kernel-smoke-results.json').read_text())}
    records=json.loads((a.work/'boot-overlays.json').read_text());manifest={'version':1,'images':{}}
    assets={
        'install-target.sh':'ventoy-e610/install-target.sh','verify.sh':'ventoy-e610/verify.sh',
        'prepare-live.sh':'ventoy-e610/prepare-live.sh','live-hook.sh':HOOK,
        'dracut-hook.sh':'usr/lib/dracut/hooks/pre-pivot/99-zz-ventoy-e610.sh',
        'finish-debian':'usr/lib/finish-install.d/94ventoy-e610'}
    for record in records:
        assert record['status']=='assembled',record
        files={}
        with tarfile.open(record['archive']) as tar:
            for m in tar:
                assert m.isfile() and not m.name.startswith('/') and '..' not in P(m.name).parts
                files[m.name]=(tar.extractfile(m).read(),m.mode)
        for source,target in assets.items():files[target]=((a.work/'assets'/source).read_bytes().replace(b'\r\n',b'\n'),0o755)
        for boot in record['boots']:
            k=boot['kernel'];test=tests[k]
            assert test['status']=='passed' and test['module_sha256']==boot['module_sha256'],k
            folder=a.work/'drivers'/k;data=(folder/'ixgbe.ko').read_bytes();assert digest(data)==test['module_sha256']
            prefix='ventoy-e610/drivers/'+k+'/'
            files[prefix+'ixgbe.ko']=(data,0o644)
            files[prefix+'SHA256SUMS']=((digest(data)+'  ixgbe.ko\n').encode(),0o644)
            for name in ['E610-MOK.der']:
                if (folder/name).is_file():files[prefix+name]=((folder/name).read_bytes(),0o644)
        name=hashlib.sha256(record['iso'].encode()).hexdigest()[:20]+'.tar.gz'
        with (a.out/name).open('wb') as out:
            with gzip.GzipFile(fileobj=out,mode='wb',mtime=0) as gz:
                with tarfile.open(fileobj=gz,mode='w',format=tarfile.USTAR_FORMAT) as tar:
                    for path,(data,mode) in sorted(files.items()):
                        h=tarfile.TarInfo(path);h.mode=mode;h.size=len(data);tar.addfile(h,io.BytesIO(data))
        iso=a.iso_root/record['iso'];st=iso.stat()
        manifest['images'][record['iso']]={'archive':name,'sha256':digest((a.out/name).read_bytes()),'iso_size':st.st_size,'iso_mtime_ns':st.st_mtime_ns}
        print(record['iso'],len(record['boots']),'kernels',flush=True)
    (a.out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')

if __name__=='__main__':main()

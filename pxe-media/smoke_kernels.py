#!/usr/bin/env python3
"""Load and unload each exact module under its ISO kernel, without target disks.

This proves ABI/module initialization only. QEMU does NOT emulate an E610 NIC.
"""
import argparse, concurrent.futures, gzip, hashlib, json, lzma, pathlib, subprocess
from assemble_boot import cpio
P=pathlib.Path

def load(job, work, busybox, qemu):
    k, record, boot = job
    dest=work/'kernel-smoke'/k;dest.mkdir(parents=True,exist_ok=True)
    files=[(d,b'',0o40755) for d in ['bin','dev','proc','sys','tmp','modules']]
    files += [('bin/busybox',busybox.read_bytes(),0o100755),('bin/sh',b'busybox',0o120777)]
    commands=[]
    for index,line in enumerate(boot['order'].splitlines()):
        if not line.startswith('insmod '):continue
        p=P(line.split()[1]);data=p.read_bytes()
        if p.suffix=='.xz':data=lzma.decompress(data)
        elif p.suffix=='.gz':data=gzip.decompress(data)
        elif p.suffix=='.zst':data=subprocess.run(['zstd','-dc'],input=data,capture_output=True,check=True).stdout
        name='modules/%02d-%s'%(index,p.name.split('.ko')[0]+'.ko')
        files.append((name,data,0o100644));commands.append('insmod /'+name)
    assert commands and commands[-1].endswith('-ixgbe.ko'),commands
    script='''#!/bin/sh
export PATH=/bin
/bin/busybox --install -s /bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
exec </dev/console >/dev/console 2>&1
echo E610_SMOKE_START
failed() { echo E610_SMOKE_FAIL; dmesg | tail -n 45; poweroff -f; }
set -e
trap failed EXIT
'''
    script+='\n'.join(commands[:-1])+'\n'
    script+='for cycle in 1 2 3; do\n'+commands[-1]+'\n'
    script+='test "$(cat /sys/module/ixgbe/version)" = 6.4.5\ngrep "^ixgbe " /proc/modules\nrmmod ixgbe\n! grep -q "^ixgbe " /proc/modules\ndone\n'
    script+='echo E610_SMOKE_PASS kernel=$(uname -r) cycles=3 hardware=unavailable\ntrap - EXIT\npoweroff -f\n'
    files.append(('init',script.encode(),0o100755));(dest/'initrd.gz').write_bytes(cpio(files))
    kernel=P(record['work'])/('vmlinuz-'+str(boot['initrd_index']))
    args=[qemu,'-name','e610-abi-'+k,'-machine','q35,accel=kvm','-cpu','host','-m','768','-smp','2','-nodefaults','-no-reboot','-display','none','-serial','stdio','-monitor','none','-kernel',str(kernel),'-initrd',str(dest/'initrd.gz'),'-append','console=ttyS0,115200 rdinit=/init panic=-1']
    result={'kernel':k,'iso':record['iso'],'module_sha256':boot['module_sha256'],'hardware_e610':'not_tested'}
    try:
        r=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=100)
        (dest/'serial.log').write_bytes(r.stdout)
        result['status']='passed' if b'E610_SMOKE_PASS kernel='+k.encode()+b' cycles=3' in r.stdout else 'failed'
        result['exit_code']=r.returncode
    except subprocess.TimeoutExpired as e:
        (dest/'serial.log').write_bytes(e.stdout or b'');result['status']='timeout'
    (dest/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(k,result['status'],flush=True);return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--work',type=P,required=True);p.add_argument('--busybox',type=P,required=True);p.add_argument('--qemu',default='/usr/libexec/qemu-kvm');p.add_argument('--retry',action='store_true');a=p.parse_args()
    inventory={r['iso']:r for r in json.loads((a.work/'audit/inventory-v2.json').read_text())};jobs={}
    for r in json.loads((a.work/'boot-overlays.json').read_text()):
        if r['status']!='assembled':continue
        for b in r['boots']:jobs.setdefault(b['kernel'],(b['kernel'],inventory[r['iso']],b))
    def test(j):
        old=a.work/'kernel-smoke'/j[0]/'result.json'
        if a.retry and old.exists() and json.loads(old.read_text()).get('status')=='passed':return json.loads(old.read_text())
        return load(j,a.work,a.busybox,a.qemu)
    with concurrent.futures.ThreadPoolExecutor(2) as pool:result=list(pool.map(test,jobs.values()))
    (a.work/'kernel-smoke-results.json').write_text(json.dumps(result,indent=2)+'\n')

if __name__=='__main__':main()

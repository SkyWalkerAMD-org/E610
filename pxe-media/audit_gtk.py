#!/usr/bin/env python3
"""Audit Debian graphical installer paths in addition to text/PXE paths."""
import argparse, hashlib, json, pathlib, subprocess
from audit_v2 import inspect
P=pathlib.Path
def main():
 p=argparse.ArgumentParser();p.add_argument('--work',type=P,required=True);p.add_argument('--iso-root',type=P,required=True);a=p.parse_args()
 records=json.loads((a.work/'audit/inventory-v2.json').read_text())
 for rec in records:
  if not rec['iso'].startswith('Debian/'):continue
  folder=P(rec['work']);paths=[s.strip().strip("'") for s in (folder/'iso-files.txt').read_text().splitlines()]
  path='/install.amd/gtk/initrd.gz'
  if path not in paths or any(b['initrd']==path for b in rec['boots']):continue
  index=len(rec['boots']);dest=folder/('initrd-'+str(index));kernel=folder/('vmlinuz-'+str(index))
  subprocess.run(['xorriso','-osirrox','on','-indev',str(a.iso_root/rec['iso']),'-extract',path,str(dest)],capture_output=True,check=True)
  kernel.symlink_to(folder/'vmlinuz-0')
  rec['boots'].append({'initrd':path,'kernel_path':'/install.amd/vmlinuz','initrd_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'kernel_sha256':rec['boots'][0]['kernel_sha256'],'modules':[]})
  inspect(rec,a.iso_root)
 (a.work/'audit/inventory-v2.json').write_text(json.dumps(records,indent=2)+'\n')
if __name__=='__main__':main()

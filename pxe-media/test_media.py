import gzip, lzma, pathlib, subprocess, unittest, ctypes, tempfile, shutil, os
from assemble_boot import cpio, copy_boot_tree
from media_lib import initramfs_files, normalize_for_append, file_path, rewrite_initramfs_files, cpio_entries

class Archives(unittest.TestCase):
    def test_el10_hook_does_not_shadow_deferred_symlink(self):
        from bake_iso import embed_initrd, resolve_payload_paths
        dirs=['usr','usr/bin','usr/lib','usr/lib/dracut','var','var/lib','var/lib/dracut','var/lib/dracut/hooks','var/lib/dracut/hooks/pre-pivot']
        original=[(n,b'',0o40755) for n in dirs]
        original += [('init',b'init',0o100755),('usr/bin/udevadm',b'ELF',0o100755),
                     ('usr/lib/dracut/hooks',b'../../../var/lib/dracut/hooks',0o120777),
                     ('usr/lib/systemd/systemd-udevd',b'../../bin/udevadm',0o120777)]
        result=embed_initrd(cpio(original),{'usr/lib/dracut/hooks/pre-pivot/e610.sh':(b'hook',0o100755)},False,True)
        rows=list(initramfs_files(result))
        self.assertFalse(any(n.startswith('usr/lib/dracut/hooks/') for n,_,_ in rows))
        self.assertEqual([d for n,_,d in rows if n=='var/lib/dracut/hooks/pre-pivot/e610.sh'],[b'hook'])
        self.assertEqual([(m,d) for n,m,d in rows if n=='usr/lib/dracut/hooks'],[(0o120777,b'../../../var/lib/dracut/hooks')])
        for links in ({'a':'b','b':'a'},{'a':'../../escape'}):
            with self.assertRaises(ValueError): resolve_payload_paths({'a/file':(b'x',0o100644)},links)
        with self.assertRaises(ValueError):
            resolve_payload_paths({'a/file':(b'x',0o100644),'b/file':(b'y',0o100644)},{'a':'b'})

    def test_el_payload_is_inside_first_main_cpio(self):
        from bake_iso import embed_initrd
        early=gzip.decompress(cpio([('microcode',b'ucode',0o100644)]))
        raw=cpio([('init',b'init',0o100755),('usr',b'',0o40755),('usr/lib/modules/k/modules.dep',b'old',0o100644)])
        payload={'ventoy-e610/prepare-live.sh':(b'hook',0o100755),'usr/lib/modules/k/modules.dep':(b'updated',0o100644)}
        result=embed_initrd(early+raw,payload,False,True)
        self.assertTrue(result.startswith(early))
        first=list(cpio_entries(gzip.decompress(result[len(early):])))
        self.assertEqual([d for n,_,d,_ in first if n=='ventoy-e610/prepare-live.sh'],[b'hook'])
        self.assertEqual([d for n,_,d,_ in first if n=='usr/lib/modules/k/modules.dep'],[b'updated'])
        self.assertEqual(sum(n=='TRAILER!!!' for n,_,_,_ in first),1)
        with self.assertRaises(ValueError):rewrite_initramfs_files(raw,{}, {'init':(b'x',0o100755)})

    def test_ubuntu_native_order_survives_first_entry_readers(self):
        from bake_iso import embed_initrd
        original=b'#!/bin/sh\necho native-init\n'
        order=b'/scripts/init-bottom/original\n'
        raw=cpio([('init',original,0o100755),('scripts/init-bottom/ORDER',order,0o100755)])
        payload={'ventoy-e610/ubuntu-stage.sh':(b'#!/bin/sh\nexit 0\n',0o100755)}
        rows=list(initramfs_files(embed_initrd(raw,payload,True)))
        self.assertEqual([d for n,_,d in rows if n=='init'],[original])
        scripts=[d for n,_,d in rows if n=='scripts/init-bottom/ORDER']
        self.assertEqual(len(scripts),1)
        self.assertTrue(scripts[0].startswith(order))
        self.assertIn(b'/bin/sh /ventoy-e610/ubuntu-stage.sh "$rootmnt"',scripts[0])
        self.assertIn(b'exit 1',scripts[0])
        self.assertEqual([d for n,_,d in rows if n=='ventoy-e610/ubuntu-stage.sh'],[payload['ventoy-e610/ubuntu-stage.sh'][0]])

    def test_rewrite_keeps_one_script_and_preserves_hardlink_metadata(self):
        raw=bytearray(gzip.decompress(cpio([('scripts/init-bottom/ORDER',b'old\n',0o100755),('busybox',b'ELF-content',0o100755),('sh',b'',0o100755)])))
        pos=0;unchanged=[]
        for name,mode,data,end in cpio_entries(raw):
            if name in ('busybox','sh'):
                raw[pos+6:pos+14]=b'0000abcd';raw[pos+38:pos+46]=b'00000002'
                unchanged.append(bytes(raw[pos:end]))
            pos=end
        early=gzip.decompress(cpio([('early',b'microcode',0o100644)]))
        frames=[gzip.compress(raw),lzma.compress(raw),subprocess.run(['zstd','-qc'],input=raw,capture_output=True,check=True).stdout]
        for frame in frames:
            result=rewrite_initramfs_files(early+frame,{'scripts/init-bottom/ORDER':b'new and longer\n'})
            rows=list(initramfs_files(result))
            self.assertEqual([d for n,_,d in rows if n=='scripts/init-bottom/ORDER'],[b'new and longer\n'])
            self.assertTrue(result.startswith(early))
            plain=gzip.decompress(result[len(early):])
            for entry in unchanged:self.assertIn(entry,plain)
        with self.assertRaises(ValueError):rewrite_initramfs_files(bytes(raw),{'missing':b'x'})
        with self.assertRaises(ValueError):rewrite_initramfs_files(bytes(raw),{'busybox':b'x'})
        with self.assertRaises(ValueError):rewrite_initramfs_files(bytes(raw)*2,{'scripts/init-bottom/ORDER':b'x'})

    def test_merged_usr_keeps_installer_and_udeb_modules(self):
        with tempfile.TemporaryDirectory() as temp:
            source=pathlib.Path(temp)/'source';root=pathlib.Path(temp)/'root'
            entries={'usr/lib/modules/k/modules.builtin':b'kernel/fb.ko\n',
                     'usr/lib/modules/k/kernel/display.ko':b'display',
                     'lib/modules/k/kernel/nic.ko':b'nic'}
            for name,data in entries.items():
                file=source/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(data)
            copy_boot_tree(source,root,True)
            self.assertTrue((root/'lib').is_symlink())
            self.assertEqual((root/'lib/modules/k/modules.builtin').read_bytes(),b'kernel/fb.ko\n')
            self.assertEqual((root/'lib/modules/k/kernel/display.ko').read_bytes(),b'display')
            self.assertEqual((root/'usr/lib/modules/k/kernel/nic.ko').read_bytes(),b'nic')
            (source/'lib/modules/k/kernel/display.ko').write_bytes(b'conflicting-display')
            with self.assertRaisesRegex(AssertionError,'Conflicting merged module'):
                copy_boot_tree(source,pathlib.Path(temp)/'conflict',True)

    def test_mixed_compression_and_override(self):
        early=gzip.decompress(cpio([('early',b'ucode',0o100644)]))
        main=gzip.decompress(cpio([('init',b'old',0o100755)]))
        overlay=cpio([('init',b'new',0o100755),('driver',b'ko',0o100644)])
        frames=[gzip.compress(main),lzma.compress(main),
                subprocess.run(['zstd','-q','-c'],input=main,capture_output=True,check=True).stdout]
        for frame in frames:
            with self.subTest(magic=frame[:5]):
                blob=early+b'\0'*17+frame+overlay
                entries=list(initramfs_files(blob))
                self.assertEqual([n for n,_,_ in entries],['early','init','init','driver'])
                self.assertEqual(dict((n,d) for n,_,d in entries)['init'],b'new')
                self.assertEqual(normalize_for_append(blob),blob)

    def test_bad_inputs_fail(self):
        with self.assertRaises(ValueError):list(initramfs_files(b'not an archive'))
        with self.assertRaises(ValueError):file_path(pathlib.Path('/tmp/root'),'../outside')
        with self.assertRaises(ValueError):file_path(pathlib.Path('/tmp/root'),'/absolute')

    def test_legacy_lz4_keeps_original_inode_records(self):
        raw=bytearray(gzip.decompress(cpio([('init',b'shell',0o100755)])))
        raw[6:14]=b'0000abcd';raw[38:46]=b'00000002'
        lib=ctypes.CDLL('liblz4.so.1');fn=lib.LZ4_compress_default
        fn.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_int,ctypes.c_int]
        fn.restype=ctypes.c_int;buffer=ctypes.create_string_buffer(len(raw)*2)
        n=fn(bytes(raw),buffer,len(raw),len(buffer));self.assertGreater(n,0)
        legacy=b'\x02\x21\x4c\x18'+n.to_bytes(4,'little')+buffer.raw[:n]
        self.assertEqual(gzip.decompress(normalize_for_append(legacy)),bytes(raw))

    def test_el7_prepare_without_chmod(self):
        source=pathlib.Path(__file__).parent/'assets/prepare-live.sh'
        with tempfile.TemporaryDirectory() as temp:
            root=pathlib.Path(temp)/'root';tools=pathlib.Path(temp)/'tools';tools.mkdir()
            for name in ('mkdir','cp','cat'):(tools/name).symlink_to(shutil.which(name))
            (root/'etc').mkdir(parents=True);(root/'etc/os-release').write_text('ID=centos\n')
            (root/'usr/share/anaconda/post-scripts').mkdir(parents=True)
            p=subprocess.run(['/bin/sh',str(source),str(root)],env=dict(os.environ,PATH=str(tools)),capture_output=True,text=True)
            self.assertEqual(p.returncode,0,p.stderr)
            self.assertIn('install-target.sh',(root/'usr/share/anaconda/post-scripts/98-ventoy-e610.ks').read_text())

if __name__=='__main__':unittest.main()

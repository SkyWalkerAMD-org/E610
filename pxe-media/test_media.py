import gzip, lzma, pathlib, subprocess, unittest, ctypes, tempfile, shutil, os
from assemble_boot import cpio
from media_lib import initramfs_files, normalize_for_append, file_path

class Archives(unittest.TestCase):
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

import importlib.util,io,pathlib,tarfile,tempfile,unittest
spec=importlib.util.spec_from_file_location('extract',pathlib.Path(__file__).with_name('e610-extract.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ExtractTests(unittest.TestCase):
    def test_archive_boundaries(self):
        for name,link in [('payload/valid',False),('../escape',False),('/absolute',False),('payload/link',True)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp:
                root=pathlib.Path(temp);archive=io.BytesIO()
                with tarfile.open(fileobj=archive,mode='w:gz') as out:
                    h=tarfile.TarInfo(name)
                    if link:h.type=tarfile.SYMTYPE;h.linkname='/etc/shadow'
                    else:h.size=2
                    out.addfile(h,None if link else io.BytesIO(b'ok'))
                source=root/'driver.run';source.write_bytes(b'#!/bin/bash\n__E610_PAYLOAD_BELOW__\n'+archive.getvalue())
                target=root/'target';target.mkdir()
                if name=='payload/valid':
                    result=pathlib.Path(module.extract(str(source),str(target)))
                    self.assertEqual((result/'valid').read_bytes(),b'ok')
                else:
                    with self.assertRaises(ValueError):module.extract(str(source),str(target))
if __name__=='__main__':unittest.main()

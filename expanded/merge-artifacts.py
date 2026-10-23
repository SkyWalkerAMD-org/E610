"""Replace complete per-media artifact trees, never mix signing attempts."""
import json
from pathlib import Path
import shutil
import sys

base, rebuilt = (Path(p).resolve() for p in sys.argv[1:])
known = {t['id'] for t in json.loads((Path(__file__).parent / 'inventory.json').read_text())}
for source in rebuilt.iterdir():
    assert source.is_dir() and not source.is_symlink() and source.name in known, source
    result = json.loads((source / 'media-result.json').read_text())
    assert result['complete'] and result['id'] == source.name, source
    destination = base / source.name
    assert destination.parent.resolve() == base and not destination.is_symlink()
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    print('Replaced complete validated media:', source.name)

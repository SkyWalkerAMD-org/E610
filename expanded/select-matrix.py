import json
import os
from pathlib import Path

inventory = json.loads(Path('output/inventory.json').read_text())
names = {t['id'] for t in inventory}
selection = os.environ.get('SELECTED_TARGETS', '')
selected = set(selection.split(',')) if selection else names
assert selected and selected <= names, selected - names
matrix = [{'id': t['id']} for t in inventory if t['id'] in selected]
with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
    stream.write('matrix=' + json.dumps(matrix, separators=(',', ':')) + '\n')

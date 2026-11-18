#!/usr/bin/env python3
"""Build an isolated consumer with only the two exported libraries."""
from pathlib import Path
import http.server
import hashlib
import json
import os
import re
import shutil
import socketserver
import subprocess
import tempfile
import threading
from project import ROOT, toolchain, libraries_ready

archives = ROOT / 'dist/libraries'
served = ROOT / '.tools' / 'layer-consumer-libraries'
served.mkdir(parents=True, exist_ok=True)
if not libraries_ready(): raise SystemExit('Resolve and validate pinned third-party libraries first')
lock = json.loads((ROOT/'docs/planning/dependencies.json').read_text())
manifest_path = archives/'manifest.json'
if not manifest_path.exists():
    raise SystemExit('Run python3 scripts/export-libraries.py first')
manifest = {item['name']: item for item in json.loads(manifest_path.read_text())}
missing = [name for name in ('defold-framework', 'defold-tycoon-ui') if name not in manifest]
if missing:
    raise SystemExit(f'manifest.json lacks entries for: {", ".join(missing)}')

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs): super().__init__(*args, directory=str(served), **kwargs)
    def log_message(self, *_): pass

class Server(socketserver.ThreadingTCPServer): allow_reuse_address = True
for index, lib in enumerate(lock['libraries']):
    prefix = hashlib.sha1(lib['url'].encode()).hexdigest()
    source = next((ROOT/'.internal/lib').glob(prefix+'-*.zip'))
    (served/f'upstream-{index}.zip').write_bytes(source.read_bytes())
for name in ('defold-framework', 'defold-tycoon-ui'):
    (served/manifest[name]['file']).write_bytes((archives/manifest[name]['file']).read_bytes())
with Server(('127.0.0.1', 0), Handler) as server:
    threading.Thread(target=server.serve_forever, daemon=True).start()
    with tempfile.TemporaryDirectory(prefix='defold-two-layer-') as directory:
        consumer = Path(directory)
        shutil.copytree(ROOT/'examples/miner', consumer/'examples/miner')
        shutil.copytree(ROOT/'assets', consumer/'assets')
        project = (ROOT/'game.project').read_text()
        project = project.replace('include_dirs = framework game_modules','')
        url = f'http://127.0.0.1:{server.server_address[1]}'
        upstream_count = len(lock['libraries'])
        for index in range(upstream_count):
            project = re.sub(rf'dependencies#{index} = .*', f'dependencies#{index} = {url}/upstream-{index}.zip', project)
        layer_deps = ''.join(
            f'dependencies#{upstream_count + offset} = {url}/{manifest[name]["file"]}\n'
            for offset, name in enumerate(('defold-framework', 'defold-tycoon-ui')))
        location = project.find('[project]\n') + len('[project]\n')
        project = project[:location] + layer_deps + project[location:]
        (consumer/'game.project').write_text(project)
        output = ROOT/'logs/layers-consumer-build.log'
        with output.open('w') as log:
            result = subprocess.run(toolchain()+['--root',str(consumer),'--output','build',
                '--platform','arm64-macos','--variant','debug','resolve','build'],
                cwd=consumer,stdout=log,stderr=subprocess.STDOUT,timeout=180)
        if result.returncode:
            print(output.read_text()[-4000:]); raise SystemExit(result.returncode)
        print('PASS: isolated consumer compiled using framework and tycoon ZIP libraries')

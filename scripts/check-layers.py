#!/usr/bin/env python3
"""Guard the lean dependency: build a minimal consumer that sees ONLY the two library ZIPs.

Why a synthetic consumer instead of `templates/miner`:
the templates need a 22 MB font that is deliberately not in git, so building one of them here
would fail for reasons unrelated to library packaging. This consumer has no GUI and no font —
it just `require`s real modules from both layers, which is exactly what packaging can break.

Checks, in order:
  1. `dist/libraries/manifest.json` exists (run export-libraries.py first)
  2. the two ZIPs expose `framework.*` / `game_modules.tycoon.*` to `require`
  3. bob compiles the consumer against only codeload upstream + the two local ZIPs
  4. nothing from `templates/` leaks into the dependency

    python3 scripts/check-layers.py
    python3 scripts/check-layers.py --bob /path/to/bob.jar
"""
from __future__ import annotations

import argparse
import http.server
import json
import pathlib
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
ARCHIVES = ROOT / 'dist' / 'libraries'
UPSTREAM = [
    'https://codeload.github.com/Insality/druid/zip/9a5171377fc2f7fba68fea4f2c117ee6a25d28a4',
    'https://codeload.github.com/britzl/monarch/zip/5c33c39830489925493163e741d5b22b4e5e3b9d',
    'https://codeload.github.com/Insality/defold-event/zip/384813497c25ff41d34ab1efdb1163217dc9dd26',
]
REQUIRES = ['framework.core.app', 'framework.core.event_bus', 'framework.ui.theme',
            'framework.save.save_manager', 'framework.platform.reward_ad',
            'game_modules.tycoon.ui.upgrade_list']

# Literal `require "x"` calls on purpose: bob resolves modules statically, so a dynamic
# `pcall(require, name)` would leave them out of the build and make this check vacuous.
CONSUMER_SCRIPT = '\n'.join(
    [f'local m{i} = require "{name}"\nprint("LAYERS_OK {name} " .. type(m{i}))'
     for i, name in enumerate(REQUIRES)] + ['print("LAYERS_PASS")']) + '\n'


def find_bob(explicit: str | None) -> str:
    for candidate in (explicit, str(ROOT / '.tools/bob.jar'),
                      str(ROOT.parent / 'platformer-game/.tools/bob.jar')):
        if candidate and pathlib.Path(candidate).exists():
            return candidate
    raise SystemExit('bob.jar not found; pass --bob or drop it in .tools/ (238 MB, gitignored)')


def find_java() -> str:
    bundled = sorted(pathlib.Path('/Applications/Defold.app/Contents/Resources/packages').glob('jdk-*/bin/java'))
    if bundled:
        return str(bundled[-1])
    java = shutil.which('java')
    if not java:
        raise SystemExit('no java found (JDK 25 validated)')
    return java


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--bob')
    args = parser.parse_args()

    manifest_path = ARCHIVES / 'manifest.json'
    if not manifest_path.exists():
        raise SystemExit('Run python3 scripts/export-libraries.py first')
    manifest = {item['name']: item for item in json.loads(manifest_path.read_text())}
    missing = [n for n in ('defold-framework', 'defold-tycoon-ui') if n not in manifest]
    if missing:
        raise SystemExit(f'manifest.json lacks: {", ".join(missing)}')

    framework_files: list[pathlib.Path] = []
    tycoon_files: list[pathlib.Path] = []

    with tempfile.TemporaryDirectory(prefix='defold-layers-') as directory:
        staged = pathlib.Path(directory) / 'served'
        staged.mkdir()
        for name in ('defold-framework', 'defold-tycoon-ui'):
            shutil.copy2(ARCHIVES / manifest[name]['file'], staged / manifest[name]['file'])

        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *a, **kw):
                super().__init__(*a, directory=str(staged), **kw)

            def log_message(self, *_):
                pass

        class Server(socketserver.ThreadingTCPServer):
            allow_reuse_address = True

        with Server(('127.0.0.1', 0), Handler) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            base = f'http://127.0.0.1:{server.server_address[1]}'
            consumer = pathlib.Path(directory) / 'consumer'
            (consumer / 'script').mkdir(parents=True)
            (consumer / 'input').mkdir()
            (consumer / 'input/game.input_binding').write_text(
                'key_trigger {\n  input: KEY_SPACE\n  action: "ok"\n}\n')
            body = '\n'.join('  ' + line for line in CONSUMER_SCRIPT.splitlines())
            (consumer / 'script/consumer.script').write_text(
                f'function init(self)\n{body}\nend\n')
            (consumer / 'main.collection').write_text(
                'name: "main"\nscale_along_z: 0\n'
                'embedded_instances {\n  id: "consumer"\n  data: "components {\\n"\n'
                '  "  id: \\"main\\"\\n"\n  "  component: \\"/script/consumer.script\\"\\n"\n'
                '  "}\\n"\n  ""\n}\n')
            deps = [f'dependencies#{i} = {url}' for i, url in enumerate(UPSTREAM)]
            deps += [f'dependencies#{len(UPSTREAM) + i} = {base}/{manifest[name]["file"]}'
                     for i, name in enumerate(('defold-framework', 'defold-tycoon-ui'))]
            (consumer / 'game.project').write_text('\n'.join(
                ['[project]', 'title = layers-consumer', 'version = 0.0.1', *deps, '',
                 '[bootstrap]', 'main_collection = /main.collectionc', '',
                 '[display]', 'width = 320', 'height = 480', '']))

            log_path = ROOT / 'logs/layers-check.log'
            log_path.parent.mkdir(parents=True, exist_ok=True)
            with log_path.open('w') as log:
                result = subprocess.run(
                    [find_java(), '-jar', find_bob(args.bob), '--root', str(consumer), '--output',
                     'build', '--platform', 'arm64-macos', '--variant', 'debug', 'resolve', 'build'],
                    cwd=consumer, stdout=log, stderr=subprocess.STDOUT, timeout=600)
            if result.returncode:
                print(log_path.read_text()[-3000:])
                raise SystemExit(f'FAILED: isolated consumer did not build (log: {log_path})')

            built = consumer / 'build'
            framework_files = [p for p in built.rglob('*') if p.suffix == '.luac' and 'framework' in p.parts]
            tycoon_files = [p for p in built.rglob('*') if p.suffix == '.luac' and 'game_modules' in p.parts]
            if not framework_files:
                raise SystemExit(f'FAILED: framework modules missing from build output (log: {log_path})')
            if not tycoon_files:
                raise SystemExit(f'FAILED: game_modules/tycoon missing from build output (log: {log_path})')
            leaked = [p for p in built.rglob('*') if p.is_file() and 'templates' in p.parts]
            if leaked:
                raise SystemExit(f'FAILED: templates leaked into the dependency: {leaked[:3]}')

    print(f'PASS: consumer built with only the two library ZIPs '
          f'(framework {len(framework_files)} luac, tycoon {len(tycoon_files)} luac)')
    print(f'log: {log_path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

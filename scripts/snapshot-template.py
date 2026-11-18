#!/usr/bin/env python3
"""Refresh a `templates/<name>/` skeleton from a live game project.

The template is a snapshot, not a symlink: the live game keeps moving, the template
is refreshed on demand. Exclusions come from the template's own `template.json`
(`excludes`), so the contract lives next to the skeleton instead of in this script.

    python3 scripts/snapshot-template.py --from ../platformer-game --name platformer
    python3 scripts/snapshot-template.py --from ../platformer-game --name platformer --dry-run
"""
from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--from', dest='source', required=True, help='live project directory')
    parser.add_argument('--name', required=True, help='template name under templates/')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    source = pathlib.Path(args.source).expanduser().resolve()
    target = ROOT / 'templates' / args.name
    manifest_path = target / 'template.json'
    if not source.is_dir():
        raise SystemExit(f'not a directory: {source}')
    if not manifest_path.exists():
        raise SystemExit(f'missing manifest: {manifest_path}')
    manifest = json.loads(manifest_path.read_text())
    excludes = manifest.get('excludes', [])

    kept: list[pathlib.Path] = []
    for path in sorted(source.rglob('*')):
        relative = path.relative_to(source)
        if any(relative.match(pattern) or relative.as_posix().startswith(pattern)
               for pattern in excludes):
            continue
        if path.is_file():
            kept.append(relative)

    print(f'source : {source}')
    print(f'target : {target}')
    print(f'files  : {len(kept)}  (excluded patterns: {len(excludes)})')
    if args.dry_run:
        for relative in kept:
            print('  ', relative.as_posix())
        print('[dry-run] nothing written')
        return 0

    for relative in kept:
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, destination)

    present = {p.relative_to(target) for p in target.rglob('*') if p.is_file()}
    stale = sorted(p for p in present - set(kept)
                   if p.name != 'template.json' and not p.name.startswith('README'))
    if stale:
        print(f'\n注意：目标里有 {len(stale)} 个源项目已不存在的文件，未删除（确认后手动清理）：')
        for path in stale[:10]:
            print('  ', path.as_posix())
    print('\n已刷新。记得 git diff 看一遍再提交。')
    return 0


if __name__ == '__main__':
    sys.exit(main())

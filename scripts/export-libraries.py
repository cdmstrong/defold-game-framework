#!/usr/bin/env python3
"""Package the two runtime layers as independent Defold Library Projects.

The framework layer version tracks the published git tag of the framework
repository (this directory when it is a git checkout, else a sibling
`defold-game-framework` checkout). This keeps ZIP version semantics aligned
with GitHub tags so a ZIP named X.Y.Z always matches tag vX.Y.Z content.
Override with --framework-version / --tycoon-version when needed.
"""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo
import argparse
import hashlib
import json
import re
import subprocess

FRAMEWORK_DIR = 'framework'
TYCOON_DIR = 'game_modules'
FALLBACK_VERSIONS = {'framework': '1.1.0', 'tycoon': '0.1.0'}


def git_tag_version(repo):
    """Latest vX.Y.Z tag in a git checkout, or None if unavailable."""
    try:
        result = subprocess.run(
            ['git', '-C', str(repo), 'describe', '--tags', '--abbrev=0'],
            capture_output=True, text=True, timeout=10)
        tag = result.stdout.strip().lstrip('v') if result.returncode == 0 else ''
        return tag if re.fullmatch(r'\d+\.\d+\.\d+', tag) else None
    except Exception:
        return None


def detect_framework_version(root):
    for repo in (root, root.parent / 'defold-game-framework'):
        version = git_tag_version(repo)
        if version:
            return version, repo
    return FALLBACK_VERSIONS['framework'], None


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / 'dist' / 'libraries'
    output.mkdir(parents=True, exist_ok=True)

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--framework-version', default=None)
    parser.add_argument('--tycoon-version', default=None)
    args = parser.parse_args()

    framework_version, source_repo = detect_framework_version(root)
    if args.framework_version:
        framework_version, source_repo = args.framework_version, 'cli override'
    tycoon_version = args.tycoon_version or FALLBACK_VERSIONS['tycoon']
    print(f"framework version {framework_version} (source: {source_repo or 'fallback'}), tycoon version {tycoon_version}")

    configurations = [
        ('defold-framework', FRAMEWORK_DIR, framework_version),
        ('defold-tycoon-ui', TYCOON_DIR, tycoon_version),
    ]
    manifest = []
    for name, folder, version in configurations:
        archive = output / f'{name}-{version}.zip'
        root_name = f'{name}-{version}'
        files = sorted(p for p in (root / folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
        if not files:
            raise RuntimeError(f'No library sources: {folder}')
        project = f'[project]\ntitle = {name}\nversion = {version}\n\n[library]\ninclude_dirs = {folder}\n'
        with ZipFile(archive, 'w', compression=ZIP_DEFLATED) as z:
            for relative, data in [(Path('game.project'), project.encode())] + [(p.relative_to(root), p.read_bytes()) for p in files]:
                info = ZipInfo(f'{root_name}/{relative.as_posix()}', date_time=(2020, 1, 1, 0, 0, 0))
                info.compress_type = ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                z.writestr(info, data)
        manifest.append({'name': name, 'version': version, 'export': folder, 'file': archive.name, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'files': len(files)})

    # Drop stale archives from previous versions so dist only holds current ones.
    current = {item['file'] for item in manifest}
    for stale in output.glob('*.zip'):
        if stale.name not in current:
            stale.unlink()
            print(f"removed stale {stale.name}")

    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    for item in manifest:
        print(f"{item['file']}: {item['files']} source files, SHA-256 {item['sha256']}")


if __name__ == '__main__':
    main()

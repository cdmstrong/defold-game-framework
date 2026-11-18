#!/usr/bin/env python3
"""Create a new game project from a template in one command.

Reads `templates/<type>/template.json` and does the mechanical part of
`framework/docs/project-bootstrap.md` §1.1:

  copy skeleton  ->  rewrite identifiers  ->  reset version  ->  write dependencies#0
  ->  copy bob.jar  ->  resolve + build (assert framework luac)  ->  git init + first commit

The manifest is the contract: nothing about a specific game lives in this script.
Adding a new template = add `templates/<type>/` + `template.json`, no code change.

    python3 scripts/new-game.py --type platformer --name my-game --title "我的游戏"
    python3 scripts/new-game.py --type platformer --name my-game --dry-run
    python3 scripts/new-game.py --type platformer --name my-game --no-build --no-git
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE = ROOT.parent
DIST_BRANCH = 'fw-dist'
ALWAYS_EXCLUDE = ['.git/', 'build/', 'dist/', '.internal/', '.tools/', 'logs/', '.workbuddy/',
                  '.editor_settings', 'screenshot.png', '.DS_Store', 'template.json', 'README.md']
TEXT_SUFFIXES = {'.lua', '.script', '.gui_script', '.render_script', '.editor_script', '.project',
                 '.collection', '.collectionproxy', '.go', '.gui', '.atlas', '.font', '.label',
                 '.material', '.render', '.input_binding', '.animationset', '.tilemap', '.camera',
                 '.particlefx', '.display_profiles', '.buffer', '.fp', '.vp', '.txt', '.md', '.json'}


def git(*args: str, cwd: pathlib.Path = ROOT, check: bool = True) -> str:
    result = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)
    if check and result.returncode:
        raise SystemExit(f'git {" ".join(args)} failed: {result.stderr.strip()}')
    return result.stdout.strip()


def framework_url(override: str | None) -> str:
    """codeload URL of the lean `fw-dist` snapshot (game.project + framework/ only)."""
    if override:
        return override
    local = git('rev-parse', '--verify', '--quiet', f'refs/heads/{DIST_BRANCH}', check=False)
    remote = git('rev-parse', '--verify', '--quiet', f'refs/remotes/origin/{DIST_BRANCH}', check=False)
    if not local:
        raise SystemExit(f'no {DIST_BRANCH} branch; run scripts/publish-framework.py first')
    if remote != local:
        raise SystemExit(f'{DIST_BRANCH} is not pushed (local {local[:8]}, origin {remote[:8] or "missing"});'
                         f' run scripts/publish-framework.py')
    url = git('remote', 'get-url', 'origin').removesuffix('.git').split('github.com')[-1].lstrip(':/')
    return f'https://codeload.github.com/{url}/zip/{local}'


def template_files(source: pathlib.Path, excludes: list[str]) -> list[pathlib.Path]:
    kept = []
    for path in sorted(source.rglob('*')):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if any(relative.match(p) or relative.as_posix().startswith(p) for p in excludes):
            continue
        kept.append(relative)
    return kept


def rewrite(path: pathlib.Path, replacements: dict[str, str]) -> bool:
    if path.suffix not in TEXT_SUFFIXES:
        return False
    text = path.read_text(errors='ignore')
    updated = text
    for old, new in replacements.items():
        updated = updated.replace(old, new)
    if updated != text:
        path.write_text(updated)
        return True
    return False


def set_project_field(game_project: pathlib.Path, key: str, value: str) -> None:
    text = game_project.read_text()
    pattern = re.compile(rf'^({re.escape(key)}\s*=\s*).*$', re.M)
    if not pattern.search(text):
        raise SystemExit(f'{game_project}: no `{key}` line to rewrite')
    game_project.write_text(pattern.sub(lambda m: m.group(1) + value, text, count=1))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--type', required=True, help='templates/<type>/')
    parser.add_argument('--name', required=True, help='new project directory name')
    parser.add_argument('--title', default=None, help='game.project title (default: name)')
    parser.add_argument('--app-id', default=None, help='save/app id (default: name with _ )')
    parser.add_argument('--prefix', default=None, help='config prefix (default: app id)')
    parser.add_argument('--dst', default=None, help=f'parent directory (default: {BASE})')
    parser.add_argument('--framework-url', default=None, help='override dependencies#0')
    parser.add_argument('--fonts-from', default=str(BASE / 'platformer-game/assets/fonts'),
                        help='directory holding ArialUnicode.ttf')
    parser.add_argument('--bob-from', default=str(BASE / 'platformer-game/.tools/bob.jar'))
    parser.add_argument('--no-build', action='store_true')
    parser.add_argument('--no-git', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    source = ROOT / 'templates' / args.type
    manifest_path = source / 'template.json'
    if not manifest_path.exists():
        raise SystemExit(f'unknown template: {source} (no template.json)')
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('skeleton') != 'project':
        raise SystemExit(f'templates/{args.type} is skeleton "{manifest.get("skeleton")}": '
                         'only "project" templates can bootstrap a standalone game')

    app_id = args.app_id or args.name.replace('-', '_')
    prefix = args.prefix or app_id
    values = {'title': args.title or args.name, 'app_id': app_id, 'prefix': prefix,
              'PREFIX': prefix.upper()}

    def expand(value: str) -> str:
        return re.sub(r'\{\{(\w+)\}\}', lambda m: values[m.group(1)], value)

    # 顺序来自 manifest（dict 保序）：先替换完整标题，再替换下划线 id，最后才是前缀
    replacements = {expand(old): expand(new) for old, new in manifest.get('replace', {}).items()}

    destination = pathlib.Path(args.dst or BASE) / args.name
    # 第二遍：模板文件里直接写 {{title}} / {{root}} 这类占位符，不必塞进 manifest
    replacements.update({'{{title}}': values['title'], '{{app_id}}': app_id,
                         '{{prefix}}': prefix, '{{PREFIX}}': prefix.upper(),
                         '{{root}}': str(destination)})
    if destination.exists() and any(destination.iterdir()):
        raise SystemExit(f'destination is not empty: {destination}')

    excludes = ALWAYS_EXCLUDE + [p for p in manifest.get('excludes', []) if p not in ALWAYS_EXCLUDE]
    files = template_files(source, excludes)
    url = framework_url(args.framework_url)

    print(f'template   : templates/{args.type}  (skeleton=project)')
    print(f'destination: {destination}')
    print(f'files      : {len(files)}')
    print(f'title      : {values["title"]}')
    print(f'app_id     : {app_id}   prefix: {prefix}')
    print(f'framework  : {url}')
    print('rewrites   :', ', '.join(f'{k} -> {v}' for k, v in replacements.items()))

    if args.dry_run:
        print('\n[dry-run] nothing written')
        return 0

    for relative in files:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, target)

    touched = [p for p in destination.rglob('*') if p.is_file() and rewrite(p, replacements)]
    game_project = destination / 'game.project'
    set_project_field(game_project, 'dependencies#0', url)
    version = manifest.get('reset', {}).get('version')
    if version:
        set_project_field(game_project, 'version', version)
    print(f'\nrewritten  : {len(touched)} files, version -> {version or "(unchanged)"}')

    # AGENTS.template.md 复制时已套用替换规则，这里只是改成正式文件名
    agent_template = destination / 'AGENTS.template.md'
    if agent_template.exists():
        (destination / 'AGENTS.md').write_text(agent_template.read_text())
        agent_template.unlink()
        print('agents     : AGENTS.md 已生成（三步排障法 + 沉淀规则）')

    fonts = pathlib.Path(args.fonts_from) / 'ArialUnicode.ttf'
    font_target = destination / 'assets/fonts/ArialUnicode.ttf'
    if fonts.exists():
        font_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(fonts, font_target)
        print(f'font       : copied {fonts.name} ({fonts.stat().st_size // 1024 // 1024} MB)')
    else:
        print(f'font       : MISSING — copy ArialUnicode.ttf into {font_target.parent} before building')

    bob_source = pathlib.Path(args.bob_from)
    if bob_source.exists():
        (destination / '.tools').mkdir(exist_ok=True)
        shutil.copy2(bob_source, destination / '.tools/bob.jar')
        print(f'bob        : copied {bob_source}')

    if not args.no_build:
        java = next(iter(sorted(pathlib.Path(
            '/Applications/Defold.app/Contents/Resources/packages').glob('jdk-*/bin/java'))), None)
        if java is None:
            raise SystemExit('no bundled JDK found; pass --no-build and build manually')
        verify = manifest.get('verify', {})
        platform = 'arm64-macos'
        steps = [
            ['resolve'],
            ['--output', f'build/{platform}', '--platform', platform, '--variant', 'debug', '--archive'],
        ]
        for step in steps:
            result = subprocess.run([str(java), '-jar', str(destination / '.tools/bob.jar'),
                                     '--root', '.', *step], cwd=destination,
                                    capture_output=True, text=True)
            if result.returncode:
                print((result.stdout + result.stderr)[-2500:])
                raise SystemExit(f'build step failed: bob {" ".join(step)}')
        luac = list((destination / f'build/{platform}').rglob('framework/**/*.luac'))
        expected = verify.get('expect_min')
        print(f'build      : OK, framework luac = {len(luac)}')
        if expected and len(luac) < expected:
            raise SystemExit(f'FAILED: expected >= {expected} framework luac, got {len(luac)} '
                             '(dependency not resolved?)')

    if not args.no_git:
        if not (destination / '.git').exists():
            git('init', '-q', cwd=destination)
        git('add', '-A', cwd=destination)
        git('commit', '-q', '-m', f'feat: {values["title"]} v{version or "0.1.0"}', cwd=destination)
        print('git        : initialized + first commit')

    print(f'\n下一步：cd {destination} && 按 {manifest_path.name} 的 replace 清单裁剪玩法，'
          f'再跑一遍 build + 冒烟钩子')
    return 0


if __name__ == '__main__':
    sys.exit(main())

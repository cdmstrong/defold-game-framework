#!/usr/bin/env python3
"""Publish the lean framework dependency (only `framework/`) as an immutable commit.

Why this exists
---------------
A game declares the framework like this:

    dependencies#0 = https://codeload.github.com/<owner>/<repo>/zip/<sha>

`codeload` zips the *whole tree* of that commit, and GitHub ignores
`.gitattributes export-ignore`, so pointing at `master` drags `docs/`, `examples/`,
`templates/`, `scripts/`, `tests/` into every game's dependency.

This script maintains a second branch (`fw-dist` by default) whose tree is exactly
the lean library project:

    game.project   [library] include_dirs = framework
    framework/     ...only the runtime layer

So `zip/<fw-dist commit sha>` behaves like the ZIP produced by export-libraries.py:
`require "framework.core.app"` keeps working, and nothing else ships.

Usage
-----
    python3 scripts/publish-framework.py            # build the dist commit and push it
    python3 scripts/publish-framework.py --dry-run  # print the plan, change nothing
    python3 scripts/publish-framework.py --no-push  # commit locally, print the sha

The printed URL is what a game puts into `dependencies#0`.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
DIST_BRANCH = 'fw-dist'
FRAMEWORK_DIR = 'framework'


def git(*args: str, env: dict | None = None, check: bool = True) -> str:
    result = subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True,
                            env={**os.environ, **(env or {})})
    if check and result.returncode:
        raise SystemExit(f'git {" ".join(args)} failed: {result.stderr.strip()}')
    return result.stdout.strip()


def project_version() -> str:
    for line in (ROOT / 'game.project').read_text().splitlines():
        if line.startswith('version'):
            return line.split('=', 1)[1].strip()
    raise SystemExit('game.project has no version line')


def require_clean_tree() -> None:
    dirty = git('status', '--porcelain', '--', FRAMEWORK_DIR)
    if dirty:
        raise SystemExit(f'framework/ has uncommitted changes, commit them first:\n{dirty}')


def build_tree(version: str) -> tuple[str, str]:
    """Return (tree_sha, game_project_blob) for the lean dist tree."""
    game_project = (f'[project]\ntitle = defold-framework\nversion = {version}\n\n'
                    f'[library]\ninclude_dirs = {FRAMEWORK_DIR}\n')
    blob = subprocess.run(['git', 'hash-object', '-w', '--stdin'], cwd=ROOT, input=game_project,
                          capture_output=True, text=True, check=True).stdout.strip()
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        index = handle.name
    try:
        env = {'GIT_INDEX_FILE': index}
        git('read-tree', '--empty', env=env)
        git('read-tree', f'--prefix={FRAMEWORK_DIR}/', f'HEAD:{FRAMEWORK_DIR}', env=env)
        git('update-index', '--add', '--cacheinfo', f'100644,{blob},game.project', env=env)
        return git('write-tree', env=env), game_project
    finally:
        pathlib.Path(index).unlink(missing_ok=True)


def slug(remote: str) -> str:
    """git@github.com:owner/repo.git / https://github.com/owner/repo -> owner/repo"""
    url = git('remote', 'get-url', remote)
    url = url.removesuffix('.git')
    tail = url.split('github.com')[-1].lstrip(':/')
    if tail.count('/') < 1:
        raise SystemExit(f'cannot parse github owner/repo from {url}')
    return tail


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--version', default=None, help='defaults to game.project version')
    parser.add_argument('--branch', default=DIST_BRANCH)
    parser.add_argument('--remote', default='origin')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--no-push', action='store_true')
    args = parser.parse_args()

    version = args.version or project_version()
    require_clean_tree()
    tree, game_project = build_tree(version)
    files = git('ls-tree', '-r', '--name-only', tree).splitlines()
    if 'game.project' not in files or not any(f.startswith(f'{FRAMEWORK_DIR}/') for f in files):
        raise SystemExit('refusing to publish: dist tree is malformed')
    leaked = [f for f in files if not (f == 'game.project' or f.startswith(f'{FRAMEWORK_DIR}/'))]
    if leaked:
        raise SystemExit(f'refusing to publish: unexpected paths {leaked[:5]}')

    parent = git('rev-parse', '--verify', '--quiet', f'refs/heads/{args.branch}', check=False)
    subject = f'fw-dist v{version}: framework/ only ({len(files)} files)'
    print(f'version : {version}')
    print(f'branch  : {args.branch} (parent {parent[:8] if parent else "none"})')
    print(f'files   : {len(files)}')
    print(f'subject : {subject}')
    print('--- game.project ---')
    print(game_project, end='')

    if args.dry_run:
        print('\n[dry-run] nothing written')
        return 0

    commit_cmd = ['commit-tree', tree, '-m', subject]
    if parent:
        commit_cmd[2:2] = ['-p', parent]
    commit = git(*commit_cmd)
    git('update-ref', f'refs/heads/{args.branch}', commit)
    print(f'\ndist commit: {commit}')

    url = f'https://codeload.github.com/{slug(args.remote)}/zip/{commit}'
    if args.no_push:
        print('[no-push] branch updated locally only')
    else:
        git('push', args.remote, f'refs/heads/{args.branch}:refs/heads/{args.branch}')
        print(f'pushed to {args.remote}/{args.branch}')

    print('\n把这一行写进游戏的 game.project：')
    print(f'dependencies#0 = {url}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

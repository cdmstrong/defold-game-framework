#!/usr/bin/env python3
"""Reproducible M0 entry points. Run from any directory; failures return nonzero."""
import argparse, hashlib, json, os, pathlib, re, shutil, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
LOCK = ROOT / 'docs/planning/dependencies.json'

def manifest(): return json.loads(LOCK.read_text())
def digest(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()

def dependencies(write=False):
    p = ROOT / 'game.project'
    text = p.read_text()
    expected = [f'dependencies#{i} = {lib["url"]}' for i,lib in enumerate(manifest()['libraries'])]
    actual = re.findall(r'^dependencies#\d+\s*=.*$', text, re.M)
    if write:
        text = re.sub(r'^dependencies#\d+\s*=.*\n?', '', text, flags=re.M)
        p.write_text(text.replace('[project]\n', '[project]\n'+'\n'.join(expected)+'\n',1))
    elif actual != expected:
        raise RuntimeError('Dependency drift: run python3 scripts/project.py sync-deps')

def run(args, log=None, timeout=None, cwd=None):
    print('RUN:', ' '.join(map(str,args)), flush=True)
    if log:
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open('w') as f:
            result = subprocess.run(args, cwd=cwd or ROOT, stdout=f, stderr=subprocess.STDOUT, timeout=timeout)
        print(log.read_text()[-7000:])
    else: result = subprocess.run(args, cwd=cwd or ROOT, timeout=timeout)
    if result.returncode: raise RuntimeError(f'Command failed ({result.returncode}); log: {log}')

def toolchain():
    lock = manifest(); bob = ROOT / '.tools/bob.jar'
    if not bob.exists():
        bob.parent.mkdir(exist_ok=True)
        temp = bob.with_suffix('.download')
        run(['curl','-fL','--retry','2','--connect-timeout','15','--max-time','300','-o',str(temp),lock['bob']['url']])
        if digest(temp) != lock['bob']['sha256']: raise RuntimeError('Bob checksum mismatch')
        temp.replace(bob)
    if digest(bob) != lock['bob']['sha256']: raise RuntimeError('Bob checksum mismatch')
    bundled = pathlib.Path('/Applications/Defold.app/Contents/Resources/packages')
    candidates = sorted(bundled.glob('jdk-*/bin/java'))
    java = os.environ.get('DEFOLD_JAVA') or (str(candidates[-1]) if candidates else shutil.which('java'))
    if not java: raise RuntimeError('Set DEFOLD_JAVA to a Java executable (JDK 25 validated)')
    command = [java,'-jar',str(bob)]
    info = subprocess.check_output(command+['--version'],text=True)
    if lock['defold']['engine_sha'] not in info: raise RuntimeError('Bob engine SHA mismatch')
    return command

def libraries_ready():
    for lib in manifest()['libraries']:
        prefix = hashlib.sha1(lib['url'].encode()).hexdigest()
        cached = list((ROOT/'.internal/lib').glob(prefix+'-*.zip'))
        if not cached or any(digest(p) != lib['archive_sha256'] for p in cached):
            return False
    return True

def resolve():
    # Bob 1.14.1's URL-keyed archive cache; integrity is checked against the lock.
    if libraries_ready(): return
    for attempt in range(3):
        try:
            run(toolchain()+['--root',str(ROOT),'resolve'], ROOT/f'logs/m0/resolve-{attempt+1}.log')
        except RuntimeError:
            if libraries_ready(): return
        if libraries_ready(): return
    raise RuntimeError('Cannot obtain all pinned archives; see resolve logs')

def build(platform, bundle=False):
    dependencies()
    resolve()
    cmd = toolchain()+['--root',str(ROOT),'--output',f'build/{platform}', '--platform',platform,'--variant','debug','--archive', '--build-report-json',f'logs/m0/{platform}-report.json']
    if bundle: cmd += ['--bundle-output',f'dist/{platform}']
    cmd += ['build'] + (['bundle'] if bundle else [])
    run(cmd, ROOT/f'logs/m0/{platform}-build.log')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command',choices=['sync-deps','check-deps','build','bundle-desktop','bundle-html5','unit','integration','serve'])
    args = parser.parse_args()
    if args.command=='sync-deps': dependencies(True)
    elif args.command=='check-deps': dependencies()
    elif args.command=='build': build('arm64-macos')
    elif args.command=='bundle-desktop': build('arm64-macos',True)
    elif args.command=='bundle-html5': build('wasm-web',True)
    elif args.command=='unit':
        # Pure-Lua unit tests for framework modules (save/settings/localization/audio)
        # plus Python build-tooling tests.
        run([sys.executable,'-m','unittest','discover','-s','tests/unit','-v'],ROOT/'logs/m0/unit.log')
        import glob as _glob
        lua = shutil.which('lua')
        if not lua:
            raise RuntimeError('lua interpreter not found; pure-Lua unit tests require it')
        for test in sorted(_glob.glob(str(ROOT/'tests/lua/test_*.lua'))):
            run([lua, test], ROOT/f'logs/m0/unit-{pathlib.Path(test).stem}.log')
    elif args.command=='integration':
        # M1 runs the full navigation/pause/modal autotest; M0 is retained as a fast smoke check.
        apps=list((ROOT/'dist/arm64-macos').glob('*.app/Contents/MacOS/*'))
        if not apps: raise RuntimeError('Run bundle-desktop first')
        stage=os.environ.get('M1_AUTOTEST')
        if stage=='1':
            # M1 autotest lives in examples/ui_demo; force that entry regardless
            # of the project's current main_collection (miner is the default).
            run([str(apps[0]),str(apps[0].parents[1]/'Resources/game.projectc'),
                 '--config=bootstrap.main_collection=/examples/ui_demo/main.collectionc',
                 '--config=m1.autotest=1'],ROOT/'logs/m1/desktop-runtime.log', timeout=300, cwd=apps[0].parents[1]/'Resources')
            text=(ROOT/'logs/m1/desktop-runtime.log').read_text()
            for marker in ['M1_INTEGRATION_PASS cycles=30','M1_SHUTDOWN listeners=0']:
                if marker not in text: raise RuntimeError('Missing runtime evidence: '+marker)
            if 'M1_REJECT' in text: raise RuntimeError('M1 reported rejected navigation requests')
            if 'ERROR:' in text or 'stack traceback' in text: raise RuntimeError('Runtime reported errors')
        else:
            run([str(apps[0]),str(apps[0].parents[1]/'Resources/game.projectc'),'--config=m0.autotest=1'],ROOT/'logs/m0/desktop-runtime.log', timeout=30, cwd=apps[0].parents[1]/'Resources')
            text=(ROOT/'logs/m0/desktop-runtime.log').read_text()
            for marker in ['M0_READY','M0_INPUT 1','M0_GUI_FINAL']:
                if marker not in text: raise RuntimeError('Missing runtime evidence: '+marker)
            if 'ERROR:' in text: raise RuntimeError('Runtime reported errors')
    elif args.command=='serve':
        run([sys.executable,'-m','http.server','8765','--bind','127.0.0.1','--directory',str(ROOT/'dist/wasm-web')])
if __name__=='__main__':
    try: main()
    except (RuntimeError,subprocess.SubprocessError,OSError) as e:
        print('ERROR:',e,file=sys.stderr); sys.exit(1)

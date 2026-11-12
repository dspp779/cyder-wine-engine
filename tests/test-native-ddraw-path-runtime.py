#!/usr/bin/env python3
"""Run owned CLI fixtures against an explicit candidate, never a game or UI.

Use a new --output for independent repetition. Existing per-case results are
preserved rather than rerunning a green case. The engine, prefix and DLL/INI
paths are explicit; no registry or formal runtime changes are made.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parent.parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--runtime', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
p.add_argument('--phase', required=True, choices=['prepare', 'bootstrap', 'cases', 'cleanup'])
args = p.parse_args()
r = args.runtime.resolve(); out = args.output.resolve()
prefix = out/'prefix'; logs = out/'runs'; app = out/'app'
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
win = lambda path: 'Z:'+str(path.resolve()).replace('/', '\\')
mapping = {name: win(out/name/'ddraw.dll') for name in ['A', 'B', 'official']}
ini = {name: out/'private-ini'/f'{name}.ini' for name in ['A', 'B']}

def env(path=None, tag='A', order='n', trace=True):
    result = os.environ.copy()
    for key in ['WINELOADER','WINESERVER','WINEDLLPATH','WINEDLLOVERRIDES','WINEARCH','WINEPREFIX',
                'DYLD_LIBRARY_PATH','DYLD_FALLBACK_LIBRARY_PATH','CYDER_DDRAW_PATH','CNC_DDRAW_CONFIG_FILE','CYDER_COMPATDB_PATH']:
        result.pop(key, None)
    result.update(WINEPREFIX=str(prefix), WINELOADER=str(r/'bin/wine'), WINESERVER=str(r/'bin/wineserver'),
                  WINEDEBUG='-all,+loaddll' if trace else '-all', CYDER_COMPATDB='0', CYDER_GRAPHICS_BACKEND='wined3d',
                  TMPDIR=str(out/'tmp')+'/', WINEDLLOVERRIDES='winemenubuilder.exe=;mscoree,mshtml=;ddraw='+order)
    if path is not None:
        result['CYDER_DDRAW_PATH'] = path
        result['CNC_DDRAW_CONFIG_FILE'] = win(ini[tag])
    return result

def run(name, path=None, tag='A', order='n', exe='dynamic.exe', extra=(), boot=False):
    record = logs/(name+'.json')
    if record.exists():
        return json.loads(record.read_text())
    command = [str(r/'bin/wine'), 'wineboot.exe' if boot else str(app/exe), *extra]
    start = time.monotonic()
    with (logs/(name+'.stdout')).open('wb') as stdout, (logs/(name+'.stderr')).open('wb') as stderr:
        process = subprocess.Popen(command, cwd=app, env=env(path,tag,order,not boot), stdout=stdout, stderr=stderr)
        try:
            code = process.wait(timeout=45 if boot else 20)
        except subprocess.TimeoutExpired:
            # Only this owned direct CLI process, never another prefix/server.
            process.kill(); process.wait(); code = None
    rows = [json.loads(line) for line in (logs/(name+'.stdout')).read_text(errors='replace').splitlines() if line.startswith('{')]
    result = dict(name=name, argv=command, mapping=path, ini=win(ini[tag]) if path is not None else None,
                  order=order, nativeLauncherPID=process.pid, exit=code, elapsedSeconds=time.monotonic()-start, rows=rows)
    record.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result), flush=True)
    return result

def check(result, ids, tag=None, builtin=False, loaded=True):
    assert result['exit'] == (0 if loaded else 1), result
    assert result['rows'] and all(row['loaded']==loaded for row in result['rows']), result
    if ids is not None:
        assert [row['id'] for row in result['rows']]==ids, result
    if loaded:
        assert all(row['builtinMarker']==builtin for row in result['rows']), result
    if tag:
        assert all(row['providerINI'].lower()==win(ini[tag]).lower() and row['iniTag']==ord(tag) for row in result['rows']), result
    return result

if args.phase=='prepare':
    out.mkdir(parents=True,exist_ok=False)
    for directory in ['runs','tmp','app','A','B','official','private-ini']:
        (out/directory).mkdir()
    toolchain = ROOT/'build/llvm-mingw-20260616-ucrt-macos-universal/bin'
    source = ROOT/'tests/fixtures/native-ddraw-path'
    builds=[]
    def compile(name, arguments, arch='i686'):
        command=[str(toolchain/f'{arch}-w64-mingw32-clang'),'-std=c11','-Os','-Wall','-Wextra','-Werror',*map(str,arguments)]
        result=subprocess.run(command,capture_output=True,cwd=out)
        (out/(name+'.stdout')).write_bytes(result.stdout);(out/(name+'.stderr')).write_bytes(result.stderr)
        builds.append(dict(name=name,argv=command,exit=result.returncode))
        assert result.returncode==0, result.stderr.decode()
    compile('stock',['-shared','-DPROVIDER_ID=825657',source/'provider.c','-Wl,--out-implib,'+str(app/'libddraw.a'),'-o',app/'ddraw.dll'])
    for name,identity in [('A',825658),('B',825659)]:
        compile('provider-'+name,['-shared',f'-DPROVIDER_ID={identity}',source/'provider.c','-o',out/name/'ddraw.dll'])
        ini[name].write_text(f';{name}\n[ddraw]\nsavesettings=0\n')
        ini[name].chmod(0o444)
    compile('dynamic',['-municode',source/'probe.c','-o',app/'dynamic.exe'])
    compile('static',['-municode','-DSTATIC_IMPORT',source/'probe.c',app/'libddraw.a','-o',app/'static.exe'])
    compile('launcher64',['-municode',source/'probe.c','-o',app/'launcher64.exe'],arch='x86_64')
    archive=ROOT.parent/'app/vendor/cnc-ddraw/7.1.0.0/cnc-ddraw.zip'
    with zipfile.ZipFile(archive) as z: data=z.read('ddraw.dll')
    assert hashlib.sha256(data).hexdigest()=='85e0f7d530dfda134793a57cb3e76b0287dcc96892ee57162dd68f47283b03a9'
    (out/'official/ddraw.dll').write_bytes(data);(out/'official/ddraw.dll').chmod(0o444)
    (out/'fixture-build.json').write_text(json.dumps(builds,indent=2)+'\n')
    print('PREPARED_OWNED_FIXTURES_NOT_RUN')
else:
    assert out.is_dir() and not prefix.is_symlink()
    subprocess.run([os.sys.executable,str(ROOT/'scripts/verify-native-ddraw-capability.py'),
                    '--root',str(r),'--config',str(r/'engine-manifest.json')],check=True)
    if args.phase=='bootstrap':
        result=run('bootstrap',extra=('-u',),boot=True)
        raise SystemExit(0 if result['exit']==0 else 1)
    elif args.phase=='cleanup':
        command=[str(r/'bin/wineserver'),'-k']
        result=subprocess.run(command,cwd=out,env=env(trace=False),capture_output=True,timeout=15)
        (logs/'cleanup.stdout').write_bytes(result.stdout);(logs/'cleanup.stderr').write_bytes(result.stderr)
        (logs/'cleanup.json').write_text(json.dumps(dict(argv=command,WINEPREFIX=str(prefix),exit=result.returncode))+'\n')
        print('Own-prefix cleanup attempted:',result.returncode)
    else:
        originals={str(path):sha(path) for path in [*ini.values(),out/'official/ddraw.dll',out/'A/ddraw.dll',out/'B/ddraw.dll',app/'ddraw.dll']}
        check(run('no-env'),[825657])
        check(run('native',mapping['A']),[825658],tag='A')
        check(run('native-builtin',mapping['A'],order='n,b'),[825658],tag='A')
        check(run('builtin',mapping['A'],order='b'),[-1],builtin=True)
        check(run('static-before-entry',mapping['B'],tag='B',exe='static.exe'),[825659],tag='B')
        check(run('startup-snapshot',mapping['A'],extra=('--mutate-path',mapping['B'])),[825658],tag='A')
        check(run('startup-disabled',extra=('--mutate-path',mapping['A'])),[825657])
        check(run('missing-native-builtin',win(out/'missing/ddraw.dll'),order='n,b'),None,loaded=False)
        check(run('invalid-relative','relative\\ddraw.dll'),None,loaded=False)
        check(run('absolute-unchanged',mapping['B'],tag='B',extra=('--absolute',win(app/'ddraw.dll'))),[825657],tag='B')
        check(run('normal-child',mapping['A'],extra=('--spawn-inherit',)),[825658,825658],tag='A')
        check(run('custom-child-drop',mapping['A'],extra=('--spawn-drop',)),[825658,825657],tag='A')
        launcher=run('launcher64-no-ddraw',mapping['A'],exe='launcher64.exe',extra=('--no-load',))
        assert launcher['exit']==0 and launcher['rows'][0]['kind']=='no-ddraw-load',launcher
        record=logs/'concurrent-mapped.json'
        if not record.exists():
            jobs=[]
            for name in ['A','B']:
                stdout=(logs/f'concurrent-{name}.stdout').open('wb');stderr=(logs/f'concurrent-{name}.stderr').open('wb')
                child=subprocess.Popen([str(r/'bin/wine'),str(app/'dynamic.exe'),'--hold'],cwd=app,env=env(mapping[name],name),stdout=stdout,stderr=stderr)
                jobs.append((name,child,stdout,stderr))
            deadline=time.monotonic()+15;overlap=False
            while time.monotonic()<deadline:
                if all((logs/f'concurrent-{name}.stdout').stat().st_size for name,_,_,_ in jobs):
                    overlap=all(child.poll() is None for _,child,_,_ in jobs);break
                if any(child.poll() is not None for _,child,_,_ in jobs):break
                time.sleep(.05)
            results=[]
            for name,child,stdout,stderr in jobs:
                code=child.wait(timeout=15);stdout.close();stderr.close()
                rows=[json.loads(line) for line in (logs/f'concurrent-{name}.stdout').read_text().splitlines() if line.startswith('{')]
                result=dict(name=name,exit=code,nativeLauncherPID=child.pid,rows=rows)
                check(result,[825658 if name=='A' else 825659]*2,tag=name)
                assert rows[1]['kind']=='held-after-overlap',result
                results.append(result)
            assert overlap,results
            result=dict(name='concurrent-mapped',bothPrintedWhileBothAlive=True,prefix=str(prefix),results=results)
            record.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result),flush=True)
        official=check(run('official-CNC',mapping['official']),[-1])
        row=official['rows'][0]
        assert row['directDrawCreate'] and row['modulePath'].lower()==mapping['official'].lower()
        assert row['header96']==(out/'official/ddraw.dll').read_bytes()[:96].hex()
        assert all(sha(Path(path))==value for path,value in originals.items())
        assert sorted(path.name for path in (out/'official').iterdir())==['ddraw.dll']
        (out/'result.json').write_text(json.dumps(dict(status='PASS_CLI_NOT_GAMEPLAY',runtime=str(r),preservedInputs=originals,
            scope='Generic startup DLL path snapshot; app owns immutable INI environment. No game/UI, EXE filter or custom-env repair.'),indent=2)+'\n')
        print('PASS native ddraw runtime snapshot, mapped DLL+INI isolation and normal child inheritance')

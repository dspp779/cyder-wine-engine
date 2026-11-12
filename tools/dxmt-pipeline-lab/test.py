"""Real GPU readback and cache fallback tests; requires a desktop Wine session."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--engine',type=Path,required=True);p.add_argument('--overlay',type=Path,required=True)
p.add_argument('--output',type=Path,required=True);p.add_argument('--compatdb',type=Path,required=True)
a=p.parse_args();engine=a.engine.resolve();overlay=a.overlay.resolve();out=a.output.resolve()
if out.exists(): raise SystemExit('Use a new output directory; existing test evidence is preserved.')
out.mkdir(parents=True);prefix=out/'prefix';exe=out/'cyder-pipeline-probe.exe'
compiler=Path(os.environ['LLVM_MINGW'])/'x86_64-w64-mingw32-clang++'
subprocess.run([str(compiler),'-std=c++20','-O2','-static',str(Path(__file__).with_name('probe.cpp')),'-ld3d11','-ld3dcompiler','-lole32','-ldxgi','-o',str(exe)],check=True)
for name in ['d3d11.dll','dxgi.dll','winemetal.dll']: shutil.copy2(overlay/'x86_64-windows'/name,out/name)
env={k:v for k,v in os.environ.items() if not k.startswith(('WINE','CYDER_','CX_','DXMT_'))}
env.update(WINEPREFIX=str(prefix),WINELOADER=str(engine/'bin/wine'),WINESERVER=str(engine/'bin/wineserver'),WINEDEBUG='-all',WINEDLLOVERRIDES='d3d11,dxgi,winemetal=b;mscoree,mshtml=',WINEDLLPATH=f'{overlay}:{engine}/lib/wine',DYLD_FALLBACK_LIBRARY_PATH=f'{overlay}/x86_64-unix:{engine}/lib:{engine}/lib/wine/x86_64-unix',CYDER_GRAPHICS_BACKEND='dxmt',CX_GRAPHICS_BACKEND='dxmt',CYDER_GRAPHICS_BACKEND_PATH=str(overlay),CYDER_GRAPHICS_BACKENDS_ROOT=str(engine),CYDER_COMPATDB_PATH=str(a.compatdb.resolve()),DXMT_LOG_PATH=str(out),DXMT_SHADER_CACHE_PATH=str(out/'shaders'),MVK_CONFIG_LOG_LEVEL='0')
results=[]
def run(name,cache=None,executable=exe):
 e=env.copy()
 if cache is not None:e['DXMT_CYDER_PIPELINE_CACHE']=str(cache)
 try:
  r=subprocess.run(['/usr/bin/arch','-x86_64',str(engine/'bin/wine'),str(executable)],cwd=out,env=e,capture_output=True,text=True,timeout=90)
 except subprocess.TimeoutExpired as exc:
  partial=(exc.stdout or b'')+(exc.stderr or b'')
  (out/(name+'.log')).write_bytes(partial if isinstance(partial,bytes) else partial.encode())
  raise RuntimeError(f'{name}: timed out, not a graphics pass') from exc
 log=r.stdout+r.stderr;(out/(name+'.log')).write_text(log)
 assert r.returncode==0 and 'PASS all 4096 pixels' in log,(name,r.returncode,log[-3000:])
 item={'case':name,'pixels':4096,'hits':log.count('CYDER_PSO hit '),'misses':log.count('CYDER_PSO miss '),'saved':log.count('CYDER_PSO saved ')}
 results.append(item);print(item,flush=True);return item
try:
 cache=out/'快取 space';cache.mkdir()
 disabled=run('disabled');assert disabled['hits']==disabled['misses']==0 and not list(cache.iterdir())
 cold=run('cold',cache);assert cold['misses']==4 and cold['saved']==4
 warm=run('warm',cache);assert warm['hits']==4 and warm['misses']==0
 files=list(cache.glob('*.metalarc'));assert len(files)==4
 for f in files:f.write_bytes(b'corrupt archive fixture')
 bad=run('corrupt',cache);assert bad['misses']==4 and bad['saved']==4
 repaired=run('repaired',cache);assert repaired['hits']==4
 # Exercise the bridge NSError path too, even when a malformed fixture's receipt matches.
 for f in files:
  invalid=b'not a Metal archive';f.write_bytes(invalid)
  Path(str(f)+'.sha1').write_text(hashlib.sha1(invalid).hexdigest())
 rejected=run('invalid-archive-with-digest',cache);assert rejected['misses']==4 and rejected['saved']==4
 other=out/'unrelated-probe.exe';shutil.copy2(exe,other)
 ignored=run('unrelated-process',cache,other);assert ignored['hits']==ignored['misses']==0
 missing=out/'does-not-exist';fallback=run('missing-directory',missing);assert fallback['misses']==4 and fallback['saved']==0 and not missing.exists()
 full=out/'full';full.mkdir()
 for n in range(4096):(full/f'fixture-{n}.metalarc').write_bytes(b'x')
 bounded=run('entry-limit',full);assert bounded['misses']==4 and bounded['saved']==0
 long=out/('unicode-長路徑-'+'a'*60)/('b'*70)/('c'*70)/('d'*70);long.mkdir(parents=True)
 longcold=run('long-unicode-path',long);assert longcold['saved']==4
 longwarm=run('long-unicode-warm',long);assert longwarm['hits']==4
 evidence={'engine':str(engine),'engine_version':(engine/'version').read_text().strip(),'overlay':str(overlay),'overlay_version':(overlay/'version').read_text().strip(),'d3d11_sha256':hashlib.sha256((overlay/'x86_64-windows/d3d11.dll').read_bytes()).hexdigest(),'cases':results,'status':'passed','scope':'Synthetic D3D11 graphics only; not MapleStory performance acceptance'}
 (out/'results.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
finally:
 # Stop only this test's server, including after timeouts. Never wait on an absent server.
 subprocess.run(['/usr/bin/arch','-x86_64',str(engine/'bin/wineserver'),'-k'],env=env,capture_output=True,timeout=15)

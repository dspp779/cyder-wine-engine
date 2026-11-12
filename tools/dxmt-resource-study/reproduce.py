"""Compile and run resource upload/initialization probes in a fresh disposable Wine prefix."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess
p=argparse.ArgumentParser(description=__doc__)
for name in ('engine','overlay','compiler','compatdb','output'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--expect-overflow-bug',action='store_true',help='Characterize the known v0.80 loss at slice 9294; not a graphics pass.')
a=p.parse_args();out=a.output.resolve();engine=a.engine.resolve();overlay=a.overlay.resolve()
if out.exists():raise SystemExit('Choose a new output directory to preserve evidence.')
out.mkdir(parents=True);exe=out/'resource-probe.exe'
subprocess.run([str(a.compiler.absolute()),'-std=c++20','-O2','-static',str(Path(__file__).with_name('probe.cpp')),'-ld3d11','-ldxgi','-o',str(exe)],check=True)
for name in ('d3d11.dll','dxgi.dll','winemetal.dll'):shutil.copy2(overlay/'x86_64-windows'/name,out/name)
env={k:v for k,v in os.environ.items() if not k.startswith(('WINE','CYDER_','CX_','DXMT_'))}
env.update(WINEPREFIX=str(out/'prefix'),WINELOADER=str(engine/'bin/wine'),WINESERVER=str(engine/'bin/wineserver'),WINEDEBUG='-all',WINEDLLOVERRIDES='d3d11,dxgi,winemetal=b;mscoree,mshtml=',WINEDLLPATH=f'{overlay}:{engine}/lib/wine',DYLD_FALLBACK_LIBRARY_PATH=f'{overlay}/x86_64-unix:{engine}/lib:{engine}/lib/wine/x86_64-unix',CYDER_GRAPHICS_BACKEND='dxmt',CX_GRAPHICS_BACKEND='dxmt',CYDER_GRAPHICS_BACKEND_PATH=str(overlay),CYDER_GRAPHICS_BACKENDS_ROOT=str(engine),CYDER_COMPATDB_PATH=str(a.compatdb.resolve()),DXMT_LOG_PATH=str(out),DXMT_SHADER_CACHE_PATH=str(out/'shaders'),MVK_CONFIG_LOG_LEVEL='0')
results=[]
try:
 for name,args in [('upload',[]),('control-8192',['overflow','4']),('overflow-16384',['overflow','8'])]:
  try:
   r=subprocess.run(['/usr/bin/arch','-x86_64',str(engine/'bin/wine'),str(exe),*args],cwd=out,env=env,capture_output=True,text=True,timeout=120)
  except subprocess.TimeoutExpired as exc:
   text=(exc.stdout or b'')+(exc.stderr or b'');(out/(name+'.log')).write_bytes(text);results.append(dict(case=name,status='timeout'));break
  text=r.stdout+r.stderr;(out/(name+'.log')).write_text(text)
  if name=='upload':
   lines=[x for x in r.stdout.splitlines() if x.startswith('UPLOAD ')]
   valid=r.returncode==0 and len(lines)==10 and all('bad_rows=0' in x for x in lines)
  elif name=='control-8192':valid=r.returncode==0 and 'OVERFLOW checked=8192 mismatches=0' in text
  elif a.expect_overflow_bug:
   valid=r.returncode==1 and 'OVERFLOW checked=16384 mismatches=1' in text and 'MISMATCH slice=9294 expected=ff00244f got=00000000' in text
  else:valid=r.returncode==0 and 'OVERFLOW checked=16384 mismatches=0' in text
  item=dict(case=name,returncode=r.returncode,expectation_matched=valid,known_graphics_failure=(name=='overflow-16384' and a.expect_overflow_bug));results.append(item);print(item,flush=True)
finally:
 subprocess.run(['/usr/bin/arch','-x86_64',str(engine/'bin/wineserver'),'-k'],env=env,capture_output=True,timeout=15)
(out/'results.json').write_text(json.dumps(dict(cases=results,overlay=(overlay/'version').read_text().strip(),dll_sha256=hashlib.sha256((out/'d3d11.dll').read_bytes()).hexdigest(),scope='Synthetic resource tests; not MapleStory performance'),indent=2)+'\n')
if len(results)!=3 or not all(r.get('expectation_matched') for r in results):raise SystemExit(1)

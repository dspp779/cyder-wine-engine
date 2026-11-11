"""GPU acceptance for initializer fixes; fail before testing when Rosetta is unavailable."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, re
p=argparse.ArgumentParser(description=__doc__)
for k in ['engine','overlay','compiler','compatdb','output']:p.add_argument('--'+k,type=Path,required=True)
p.add_argument('--baseline',action='store_true',help='Confirm old overflow failure; run only original probes.')
a=p.parse_args();base=Path(__file__).parent;out=a.output.resolve();engine=a.engine.resolve();overlay=a.overlay.resolve()
try:
 r=subprocess.run(['/usr/bin/arch','-x86_64','/usr/bin/true'],capture_output=True,text=True)
except OSError as e:raise SystemExit(f'Environment unavailable before GPU tests: {e}')
if r.returncode:raise SystemExit('Rosetta/x86_64 unavailable; no GPU tests ran: '+r.stderr.strip())
if out.exists():raise SystemExit('Choose a new output directory.')
out.mkdir(parents=True);exe=out/'cyder-resource-probe.exe';overflow=out/'resource-overflow.exe'
for source,target in [(base/'initializer-probe.cpp',exe),(base.parent/'dxmt-resource-study/probe.cpp',overflow)]:
 subprocess.run([str(a.compiler.absolute()),'-std=c++20','-O2','-static',str(source),'-ld3d11','-ldxgi','-o',str(target)],check=True)
for name in ['d3d11.dll','dxgi.dll','winemetal.dll']:shutil.copy2(overlay/'x86_64-windows'/name,out/name)
env={k:v for k,v in os.environ.items() if not k.startswith(('WINE','CYDER_','CX_','DXMT_'))}
env.update(WINEPREFIX=str(out/'prefix'),WINELOADER=str(engine/'bin/wine'),WINESERVER=str(engine/'bin/wineserver'),WINEDEBUG='-all',WINEDLLOVERRIDES='d3d11,dxgi,winemetal=b;mscoree,mshtml=',WINEDLLPATH=f'{overlay}:{engine}/lib/wine',DYLD_FALLBACK_LIBRARY_PATH=f'{overlay}/x86_64-unix:{engine}/lib:{engine}/lib/wine/x86_64-unix',CYDER_GRAPHICS_BACKEND='dxmt',CX_GRAPHICS_BACKEND='dxmt',CYDER_GRAPHICS_BACKEND_PATH=str(overlay),CYDER_GRAPHICS_BACKENDS_ROOT=str(engine),CYDER_COMPATDB_PATH=str(a.compatdb.resolve()),DXMT_LOG_PATH=str(out),MVK_CONFIG_LOG_LEVEL='0')
results=[]
def run(name,path,args=(),extra=None,expected=0,marker=''):
 e=env|dict(extra or {})
 try:r=subprocess.run(['/usr/bin/arch','-x86_64',str(engine/'bin/wine'),str(path),*args],cwd=out,env=e,capture_output=True,text=True,timeout=120)
 except subprocess.TimeoutExpired as exc:
  (out/(name+'.log')).write_bytes((exc.stdout or b'')+(exc.stderr or b''));results.append(dict(case=name,status='timeout'));raise
 log=r.stdout+r.stderr;(out/(name+'.log')).write_text(log)
 valid=r.returncode==expected and marker in r.stdout
 if name.startswith('upload'):
  rows=[x for x in r.stdout.splitlines() if x.startswith('UPLOAD ')];valid &= len(rows)==10 and all('bad_rows=0' in x for x in rows)
 if extra and extra.get('DXMT_CYDER_RESOURCE_PROFILE')=='1':
  valid &= 'CYDER_RESOURCE ops=' in log
  valid &= len(re.findall(r'^CYDER_RESOURCE_FLUSH ',log,re.M))<=64
  valid &= len(re.findall(r'^CYDER_RESOURCE_COMMIT ',log,re.M))<=64
 if 'profile-off' in name:valid &= 'CYDER_RESOURCE' not in log
 if name=='fault-name-gate':valid &= 'failures=0' in log
 if name=='overflow-small-heap':
  m=re.search(r'capacity_flushes=(\d+)',log);valid &= bool(m and int(m[1])>10)
 item=dict(case=name,returncode=r.returncode,passed=bool(valid),known_baseline_failure=(a.baseline and expected!=0));results.append(item);print(item,flush=True)
 if not valid:raise RuntimeError(f'{name}: readback, exit status or diagnostics mismatch; see log')
profile={'DXMT_CYDER_RESOURCE_PROFILE':'1'}
try:
 run('upload-profile-off',overflow,marker='bad_rows=0')
 run('control-8192',overflow,['overflow','4'],marker='OVERFLOW checked=8192 mismatches=0')
 run('overflow-16384',overflow,['overflow','8'],expected=1 if a.baseline else 0,marker='OVERFLOW checked=16384 mismatches='+('1' if a.baseline else '0'))
 if not a.baseline:
  run('upload-profile-on',overflow,extra=profile,marker='bad_rows=0')
  run('mixed-profile-off',exe,['mixed'],marker='bad=0')
  run('mixed-small-heap',exe,['mixed'],extra=profile|{'DXMT_CYDER_TEST_SMALL_HEAP':'1'},marker='bad=0')
  # The same allowlisted name selects the original overflow probe for this case.
  other=out/'initializer-saved.exe';shutil.copy2(exe,other);shutil.copy2(overflow,exe)
  try:run('overflow-small-heap',exe,['overflow','8'],extra=profile|{'DXMT_CYDER_TEST_SMALL_HEAP':'1'},marker='OVERFLOW checked=16384 mismatches=0')
  finally:shutil.copy2(other,exe)
  for site in ['reserve','upload','retain','command','zero','clear']:
   mode='fault-clear' if site=='clear' else 'fault'
   for always in [False,True]:
    e=profile|{'DXMT_CYDER_TEST_FAIL':site}
    if always:e['DXMT_CYDER_TEST_FAIL_ALWAYS']='1'
    run('fault-'+site+('-permanent' if always else '-once'),exe,[mode],extra=e,marker='bad=0')
  run('fault-depth-once',exe,['fault-depth'],extra=profile|{'DXMT_CYDER_TEST_FAIL':'clear'},marker='bad=0')
  for site in ['reserve','retain','command']:
   run('fault-buffer-'+site,exe,['fault-buffer'],extra=profile|{'DXMT_CYDER_TEST_FAIL':site},marker='bad=0')
  other=out/'unrelated-resource-probe.exe';shutil.copy2(exe,other)
  run('fault-name-gate',other,['mixed'],extra=profile|{'DXMT_CYDER_TEST_FAIL':'reserve','DXMT_CYDER_TEST_FAIL_ALWAYS':'1'},marker='bad=0')
finally:
 subprocess.run(['/usr/bin/arch','-x86_64',str(engine/'bin/wineserver'),'-k'],env=env,capture_output=True,timeout=15)
 (out/'results.json').write_text(json.dumps({'cases':results,'overlay':(overlay/'version').read_text().strip(),'dll_sha256':hashlib.sha256((out/'d3d11.dll').read_bytes()).hexdigest(),'scope':'GPU correctness and diagnostics; not MapleStory performance'},indent=2)+'\n')

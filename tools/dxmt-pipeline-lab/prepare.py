"""Prepare pinned DXMT v0.80 sources and apply the optional renderer experiment."""
from pathlib import Path
import argparse, hashlib, shutil, subprocess, tarfile, tempfile
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--upstream',type=Path,required=True);p.add_argument('--gametomac',type=Path,required=True);p.add_argument('--workspace',type=Path,required=True)
a=p.parse_args()
for f,h in [(a.upstream,'79cd3a2b32749fc3890b6c2a9337f45de26fdb750014f3457bb7ebafa679492d'),(a.gametomac,'d9b2409c3d89ed594316e0284de8bf263574a199b3396863a36a5ac3663547c5')]:
 assert hashlib.sha256(f.read_bytes()).hexdigest()==h,f'Unexpected source archive: {f}'
workspace=a.workspace.resolve();source=workspace/'source'
if source.exists(): raise SystemExit('Source already exists; choose a fresh workspace.')
with tempfile.TemporaryDirectory() as tmp:
 tmp=Path(tmp)
 for archive,folder in [(a.upstream,'upstream'),(a.gametomac,'gametomac')]:
  dest=tmp/folder;dest.mkdir()
  with tarfile.open(archive) as t:
   for m in t.getmembers():
    if m.name.startswith('/') or '..' in Path(m.name).parts or m.issym() or m.islnk(): raise ValueError('Unsafe archive entry')
   t.extractall(dest)
 workspace.mkdir(parents=True,exist_ok=True)
 shutil.copytree(tmp/'upstream/dxmt-0.80',source)
 # The upstream tag archive omits submodule files. Only use this source dependency.
 shutil.copytree(tmp/'gametomac/source/libs/DXBCParser',source/'libs/DXBCParser',dirs_exist_ok=True)
 patch=Path(__file__).with_name('dxmt-v0.80-cyder-pipeline-archive.patch')
 subprocess.run(['patch','-p1','--dry-run','-i',str(patch.resolve())],cwd=source,check=True)
 subprocess.run(['patch','-p1','-i',str(patch.resolve())],cwd=source,check=True)
print(source)

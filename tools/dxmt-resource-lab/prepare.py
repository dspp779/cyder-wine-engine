"""Prepare the pinned pipeline baseline then apply the resource lab patches."""
from pathlib import Path
import argparse,subprocess,sys
p=argparse.ArgumentParser(description=__doc__)
for k in ['upstream','gametomac','workspace']:p.add_argument('--'+k,type=Path,required=True)
a=p.parse_args();here=Path(__file__).resolve().parent
subprocess.run([sys.executable,str(here.parent/'dxmt-pipeline-lab/prepare.py'),'--upstream',str(a.upstream),'--gametomac',str(a.gametomac),'--workspace',str(a.workspace)],check=True)
for name in ['01-initializer.patch','02-submission-statistics.patch']:
 for dry in [True,False]:subprocess.run(['patch','-p1',*(['--dry-run'] if dry else []),'-i',str(here/name)],cwd=a.workspace/'source',check=True)

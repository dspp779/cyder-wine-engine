#!/usr/bin/env python3
"""Bounded native-engine smoke test; a failed Windows command is a failed test."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / 'install/wine-cx26-arm64-experimental'
LOGS = ROOT / 'build/arm64-experimental-cx26/logs'

def run(command, env, timeout=25):
    process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stdout, stderr = process.communicate()
    return dict(command=command, returncode=process.returncode,
                timed_out=timed_out, stdout=stdout, stderr=stderr)

def main():
    if not (ENGINE / 'bin/wine').is_file():
        raise SystemExit('Build and install the experimental engine first.')
    LOGS.mkdir(parents=True, exist_ok=True)
    prefix = tempfile.mkdtemp(prefix='cyder-arm64-smoke-', dir='/private/tmp')
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(('WINE', 'WINEDLL', 'DYLD_')):
            env.pop(key)
    env.update(WINEPREFIX=prefix, WINESERVER=str(ENGINE / 'bin/wineserver'),
               WINELOADER=str(ENGINE / 'bin/wine'), WINEDEBUG='-all')
    results = []
    for binary, arguments in [('wine', ['--version']), ('wineserver', ['--version']),
                              ('wine', ['cmd', '/c', 'echo CYDER_ARM64_SMOKE_OK'])]:
        row = run(['/usr/bin/arch', '-arm64', str(ENGINE / 'bin' / binary), *arguments], env)
        results.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
    cleanup = run([str(ENGINE / 'bin/wineserver'), '-k'], env, timeout=10)
    passed = all(r['returncode'] == 0 and not r['timed_out'] for r in results)
    passed = passed and 'CYDER_ARM64_SMOKE_OK' in results[-1]['stdout']
    report = dict(engine=str(ENGINE), prefix=prefix, passed=passed, results=results, cleanup=cleanup)
    output = LOGS / 'smoke.json'
    if output.exists():
        output.with_suffix('.json.previous').write_text(output.read_text())
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    raise SystemExit(0 if passed else 1)

if __name__ == '__main__':
    main()

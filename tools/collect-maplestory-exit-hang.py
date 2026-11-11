#!/usr/bin/env python3
"""Read-only macOS capture of an existing MapleStory PID; never launches Wine."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import time


def identity(pid):
    libproc = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    libproc.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                   ctypes.c_void_p, ctypes.c_int]
    buf = ctypes.create_string_buffer(136)  # struct proc_bsdinfo on macOS
    if libproc.proc_pidinfo(pid, 3, 0, buf, len(buf)) != len(buf):
        raise RuntimeError('Cannot read process identity; process may have exited.')
    process_id, _, uid = struct.unpack_from('=III', buf.raw, 12)
    started = struct.unpack_from('=QQ', buf.raw, 120)
    if process_id != pid or uid != os.getuid():
        raise RuntimeError('Target must belong to the current user.')
    return (pid, uid, *started)


def run(command, timeout=15):
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          timeout=timeout, check=False)


def capture(pid, output, get_identity=identity, execute=run, pause=time.sleep):
    if pid <= 1:
        raise RuntimeError('A positive MapleStory PID is required.')
    original = get_identity(pid)
    name = execute(['/bin/ps', '-p', str(pid), '-o', 'comm='])
    if name.returncode or Path(name.stdout.decode().strip()).name.lower() != 'maplestory.exe':
        raise RuntimeError('Target is not MapleStory.exe; refusing to collect another process.')
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    manifest = {'identity': original, 'commands': [], 'status': 'collecting'}

    def collect(filename, command):
        if get_identity(pid) != original:
            raise RuntimeError('Target identity changed; collection stopped.')
        result = execute(command)
        (output / filename).write_bytes(result.stdout)
        manifest['commands'].append({'file': filename, 'command': command,
                                     'status': result.returncode})
        if result.returncode:
            raise RuntimeError('Capture failed: ' + filename)
        if get_identity(pid) != original:
            raise RuntimeError('Target exited or changed during capture.')

    try:
        for number in (1, 2):
            # -M adds a default COMMAND column on macOS; -c keeps argv out of it.
            collect(f'threads-{number}.txt', ['/bin/ps', '-M', '-c', '-p', str(pid),
                    '-o', 'pid,utime,stime,time,%cpu,state,comm'])
            collect(f'sample-{number}.txt', ['/usr/bin/sample', str(pid), '3', '1'])
            if number == 1:
                pause(2)
        collect('vmmap.txt', ['/usr/bin/vmmap', str(pid)])
        manifest['status'] = 'captured'  # evidence only, not a diagnosis
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        manifest['status'] = 'incomplete'
        manifest['error'] = str(error)
        raise
    finally:
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--out', type=Path, required=True, help='New output directory')
    args = parser.parse_args()
    try:
        capture(args.pid, args.out)
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
    print('Captured read-only evidence in ' + str(args.out.resolve()))

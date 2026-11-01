#!/usr/bin/env python3
"""Reconstruct sparse upstream patch context without vendoring unrelated code.

The hashes identify the full original CrossOver source files. Only patch context,
licence notices and the actual API bodies exercised by tests are retained.
"""
import json
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
destination.mkdir(parents=True, exist_ok=True)
for name, spec in json.loads(source.read_text()).items():
    assert Path(name).name == name
    lines = ['/* unrelated upstream source omitted from fixture */\n'] * spec['source_line_count']
    for fragment in spec['fragments']:
        start = fragment['start_line'] - 1
        lines[start:start + len(fragment['lines'])] = fragment['lines']
    (destination / name).write_text(''.join(lines))

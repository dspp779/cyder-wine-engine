#!/usr/bin/env python3
"""Prevent a capability-bearing package from containing old PE ntdll files.

This is a feature/architecture check, not a replacement for artifact signatures.
Unknown capability names are retained by the manifest and ignored here.
"""
from pathlib import Path
import argparse
import json
import struct

CAPABILITY = "native-ddraw-path-v1"
MARKER = b"CYDER_NATIVE_DDRAW_PATH_V1"

def verify(root, config):
    capabilities = json.loads(config.read_text()).get("capabilities", [])
    if not isinstance(capabilities, list) or any(not isinstance(c, str) for c in capabilities):
        raise ValueError("capabilities must be an array of strings")
    if CAPABILITY not in capabilities:
        return {"capability": CAPABILITY, "required": False}
    checked = []
    for directory, machine in [("i386-windows", 0x014c), ("x86_64-windows", 0x8664)]:
        path = root / "lib/wine" / directory / "ntdll.dll"
        data = path.read_bytes()
        if len(data) < 64 or data[:2] != b"MZ":
            raise ValueError(f"not a PE ntdll: {path}")
        pe = struct.unpack_from("<I", data, 60)[0]
        if pe + 24 > len(data) or data[pe:pe+4] != b"PE\0\0":
            raise ValueError(f"invalid PE header: {path}")
        if struct.unpack_from("<H", data, pe+4)[0] != machine or MARKER not in data:
            raise ValueError(f"missing {CAPABILITY} marker or wrong PE architecture: {path}")
        checked.append(str(path.relative_to(root)))
    return {"capability": CAPABILITY, "required": True, "checked": checked}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root", required=True, type=Path)
    p.add_argument("--config", required=True, type=Path)
    args = p.parse_args()
    try:
        print(json.dumps(verify(args.root, args.config)))
    except (OSError, ValueError, struct.error) as exc:
        p.exit(1, f"Engine capability verification failed: {exc}\n")

if __name__ == "__main__":
    main()

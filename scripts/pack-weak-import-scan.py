#!/usr/bin/env python3
"""Refuse to pack Mach-O files with unreviewed weak imports from macOS.

A symbol newer than the deployment target becomes a weak import: it is NULL on
an older macOS, and an unguarded call jumps to address 0. The minos scan cannot
see this (Cyder013's ntdll.so had minos 10.15 and still called a NULL _pipe2 on
macOS 15.8). Every weak import from /usr/lib or /System must match a reviewed
row in config/weak-import-allowlist.tsv that names its runtime guard.
Weak imports from bundled libraries (@rpath, @loader_path) are not checked.
"""
import fnmatch
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_ALLOWLIST = Path(__file__).resolve().parent.parent / "config" / "weak-import-allowlist.tsv"
SYSTEM_PREFIXES = ("/usr/lib/", "/System/")
WEAK_RE = re.compile(r"\(undefined\) weak external (\S+) \(from ([^)]+)\)")


def load_allowlist(path: Path):
    rows = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) != 3 or not all(c.strip() for c in cols):
            raise ValueError(f"{path}:{n}: expected symbol<TAB>path<TAB>guard")
        rows.append((cols[0], cols[1]))
    return rows


def short_names(install_name: str):
    """Names `nm -m` may print in `(from X)` for this load command."""
    base = install_name.rsplit("/", 1)[-1]
    names = {base, base.split(".", 1)[0]}
    m = re.search(r"/([^/]+)\.framework/", install_name)
    if m:
        names.add(m.group(1))
    return names


MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf",  # fat
}


def is_macho(path: Path) -> bool:
    # Reading the magic is much faster than `file` over thousands of PE files.
    try:
        with path.open("rb") as f:
            return f.read(4) in MACHO_MAGICS
    except OSError:
        return False


def load_commands(path: Path):
    out = subprocess.check_output(["otool", "-L", str(path)], text=True, stderr=subprocess.DEVNULL)
    return [line.strip().split(" (", 1)[0] for line in out.splitlines()[1:] if line.strip()]


def weak_imports(path: Path):
    out = subprocess.check_output(["nm", "-m", str(path)], text=True, stderr=subprocess.DEVNULL)
    return sorted(set(WEAK_RE.findall(out)))


def allowed(symbol: str, rel: str, rows) -> bool:
    return any(fnmatch.fnmatchcase(symbol, s) and fnmatch.fnmatchcase(rel, p) for s, p in rows)


def scan(root: Path, rows):
    violations = []
    for p in sorted(root.rglob("*")):
        if not p.is_file() or p.is_symlink() or not is_macho(p):
            continue
        system, bundled = set(), set()
        for name in load_commands(p):
            (system if name.startswith(SYSTEM_PREFIXES) else bundled).update(short_names(name))
        rel = p.relative_to(root).as_posix()
        for symbol, library in weak_imports(p):
            # Unknown library names count as system: fail closed.
            if library in bundled and library not in system:
                continue
            if not allowed(symbol, rel, rows):
                violations.append((rel, symbol, library))
    return violations


def main(argv) -> int:
    if len(argv) not in (2, 3):
        print(f"Usage: {argv[0]} <engine-tree> [allowlist.tsv]", file=sys.stderr)
        return 2
    root = Path(argv[1])
    allowlist = Path(argv[2]) if len(argv) == 3 else DEFAULT_ALLOWLIST
    rows = load_allowlist(allowlist)
    violations = scan(root, rows)
    if violations:
        print(
            "Refusing to pack: unreviewed weak imports from macOS (NULL on a macOS "
            "that lacks the symbol). Rebuild without the function or add a guard "
            f"and a row to {allowlist}:",
            file=sys.stderr,
        )
        for rel, symbol, library in violations:
            print(f"  {rel}: {symbol} (from {library})", file=sys.stderr)
        return 1
    print(f"OK: every macOS weak import is guarded ({allowlist.name})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""List libc/system functions that the SDK declares but the minOS floor lacks.

Autoconf `AC_CHECK_FUNCS` and Meson `cc.has_function` only test that a symbol
links. A newer SDK declares functions such as `pipe2` (SDK 27) with an
availability attribute, so the link succeeds, the build defines `HAVE_PIPE2`,
and the call becomes a weak import that is NULL on older macOS. Cyder013
crashed in `server_pipe` on macOS 15.8 this way.

This probe compiles one translation unit at the floor with clang's
availability diagnostics turned into errors and reports every checked
function that clang says is newer than the floor. Functions the included
headers do not declare are left to the build's own check; the pack gate
(`pack-weak-import-scan.py`) catches whatever slips through.

Output: one `name<TAB>introduced-version` line per unavailable function.
"""
import argparse
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

HEADERS = (
    "sys/types.h", "sys/param.h", "sys/stat.h", "sys/time.h", "sys/socket.h",
    "sys/uio.h", "sys/mman.h", "sys/mount.h", "sys/statvfs.h", "sys/event.h",
    "sys/attr.h", "sys/sysctl.h", "sys/resource.h", "sys/wait.h",
    "sys/ioctl.h", "sys/select.h", "sys/xattr.h", "sys/random.h",
    "stdio.h", "stdlib.h", "string.h", "strings.h", "wchar.h", "locale.h",
    "xlocale.h", "unistd.h", "fcntl.h", "signal.h", "time.h", "poll.h",
    "sched.h", "pthread.h", "dlfcn.h", "netdb.h", "ifaddrs.h", "termios.h",
    "pwd.h", "grp.h", "fstab.h", "spawn.h", "copyfile.h", "malloc/malloc.h",
    "net/if.h", "netinet/in.h", "arpa/inet.h", "crt_externs.h",
    "libproc.h", "mach/mach.h", "os/lock.h",
)

ONLY_AVAILABLE_RE = re.compile(r"'(\w+)' is only available on macOS ([\d.]+) or newer")
UNAVAILABLE_RE = re.compile(r"'(\w+)' is unavailable")


def configure_ac_functions(text: str):
    """Functions checked by AC_CHECK_FUNCS, WINE_CHECK_LIB_FUNCS and
    AC_CHECK_FUNC; each is overridable with `ac_cv_func_<name>=no`."""
    names = []
    for m in re.finditer(r"\b(?:AC_CHECK_FUNCS|WINE_CHECK_LIB_FUNCS)\(\s*\\?\s*([^,)]*)", text):
        names += m.group(1).replace("\\", " ").replace("[", " ").replace("]", " ").split()
    names += re.findall(r"\bAC_CHECK_FUNC\(\s*\[?(\w+)", text)
    return names


def meson_functions(text: str):
    """Functions in GLib-style `functions = [...]` and `functions += [...]`."""
    names = []
    for m in re.finditer(r"\bfunctions\s*\+?=\s*\[(.*?)\]", text, re.S):
        names += re.findall(r"'(\w+)'", m.group(1))
    return names


def probe_source(functions):
    lines = ["#define _DARWIN_C_SOURCE 1"]
    for h in HEADERS:
        lines += [f"#if __has_include(<{h}>)", f"#include <{h}>", "#endif"]
    lines.append("void cyder_minos_probe(void);")
    lines.append("void cyder_minos_probe(void) {")
    lines += [f"    (void)&{name};" for name in functions]
    lines.append("}")
    return "\n".join(lines) + "\n"


def unavailable(functions, floor: str, cc: str):
    functions = sorted(set(f for f in functions if re.fullmatch(r"\w+", f)))
    if not functions:
        return {}
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "probe.c"
        src.write_text(probe_source(functions))
        cmd = shlex.split(cc) + [
            f"-mmacosx-version-min={floor}", "-fsyntax-only", "-ferror-limit=0",
            "-Werror=unguarded-availability", "-Werror=unguarded-availability-new",
            str(src),
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
    err = proc.stderr
    if "fatal error" in err:
        raise RuntimeError(f"probe compile failed:\n{err}")
    wanted = set(functions)
    found = {}
    for name, version in ONLY_AVAILABLE_RE.findall(err):
        if name in wanted:
            found[name] = version
    for name in UNAVAILABLE_RE.findall(err):
        if name in wanted:
            found.setdefault(name, "never")
    return found


def main(argv) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--floor", required=True, help="minimum macOS, e.g. 10.15")
    ap.add_argument("--cc", default="/usr/bin/clang -arch x86_64",
                    help="compiler command used by the build")
    ap.add_argument("--configure-ac", type=Path, help="read checks from configure.ac")
    ap.add_argument("--meson-build", type=Path, help="read checks from meson.build")
    ap.add_argument("functions", nargs="*")
    args = ap.parse_args(argv[1:])

    functions = list(args.functions)
    if args.configure_ac:
        functions += configure_ac_functions(args.configure_ac.read_text())
    if args.meson_build:
        functions += meson_functions(args.meson_build.read_text())
    try:
        found = unavailable(functions, args.floor, args.cc)
    except (OSError, RuntimeError) as exc:
        print(f"minos-unavailable-funcs: {exc}", file=sys.stderr)
        return 1
    for name in sorted(found):
        print(f"{name}\t{found[name]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env bash
# Sourced by build-media-stack.sh. Keep compiler selection persistent in Meson;
# --reconfigure alone does not replace cached compilers.
media_prepare_native_file() {
  local native="$MEDIA_BUILD/cyder-native.ini" candidate
  mkdir -p "$MEDIA_BUILD"
  candidate="$(mktemp "$MEDIA_BUILD/.cyder-native.XXXXXX")"
  "${CYDER_HOST_PYTHON:-python3}" - "$candidate" "$MIN_FLAG" \
    "${CC:-/usr/bin/clang -arch x86_64}" \
    "${CXX:-/usr/bin/clang++ -arch x86_64}" \
    "${OBJC:-/usr/bin/clang -arch x86_64}" \
    "${OBJCXX:-/usr/bin/clang++ -arch x86_64}" <<'PY'
import pathlib, shlex, sys

def literal(value):
    return "'" + value.replace('\\', '\\\\').replace("'", "\\'") + "'"

def array(values):
    return '[' + ', '.join(map(literal, values)) + ']'

lines = ['[binaries]']
for language, command in zip(('c', 'cpp', 'objc', 'objcpp'), sys.argv[3:]):
    lines.append(f'{language} = {array(shlex.split(command))}')
lines.append('[built-in options]')
for language in ('c', 'cpp', 'objc', 'objcpp'):
    lines.append(f'{language}_args = {array([sys.argv[2]])}')
    lines.append(f'{language}_link_args = {array([sys.argv[2]])}')
pathlib.Path(sys.argv[1]).write_text('\n'.join(lines) + '\n')
PY
  if [[ -f "$MEDIA_BUILD/glib-build/build.ninja" ||
        -f "$MEDIA_BUILD/gstreamer-build/build.ninja" ]]; then
    if [[ ! -f "$native" ]] || ! cmp -s "$candidate" "$native"; then
      rm -f "$candidate"
      echo "Media build has an unverified or different cached toolchain: $MEDIA_BUILD" >&2
      echo "No build data removed. Use a fresh OGOM_BUILD_DIR (or inspect and move this media build aside) before changing compilers or deployment target." >&2
      return 1
    fi
  fi
  mv "$candidate" "$native"
}

# Print the Python that runs Meson. An explicit CYDER_HOST_PYTHON wins. The
# system Python stays the default, but a Homebrew Meson newer than it supports
# fails on import (typing.ParamSpec with 3.9), so fall back to the interpreter
# Meson itself was installed for.
media_host_python() {
  local meson="$1" site="$2" system="${MEDIA_SYSTEM_PYTHON:-/usr/bin/python3}" own
  if [[ -n "${CYDER_HOST_PYTHON:-}" ]]; then
    printf "%s\n" "$CYDER_HOST_PYTHON"
    return 0
  fi
  if PYTHONPATH="$site" "$system" -c "import mesonbuild.mesonlib" >/dev/null 2>&1; then
    printf "%s\n" "$system"
    return 0
  fi
  own="$(head -n 1 "$meson" 2>/dev/null | sed -n "s/^#![[:space:]]*//p")"
  own="${own%% *}"
  if [[ -n "$own" && -x "$own" ]]; then
    echo "Note: $system cannot run this Meson; using $own (set CYDER_HOST_PYTHON to override)." >&2
    printf "%s\n" "$own"
    return 0
  fi
  printf "%s\n" "$system"
}

media_verify_x86_64() {
  "${CYDER_HOST_PYTHON:-python3}" - "$1" <<'PY'
import pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
magics = {bytes.fromhex(x) for x in ('cffaedfe', 'cefaedfe', 'feedfacf', 'feedface',
                                   'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
checked = 0
for path in root.rglob('*'):
    if not path.is_file() or path.is_symlink():
        continue
    with path.open('rb') as stream:
        if stream.read(4) not in magics:
            continue
    arches = subprocess.check_output(['/usr/bin/lipo', '-archs', str(path)], text=True).split()
    if arches != ['x86_64']:
        raise SystemExit(f'Media architecture validation failed: {path}: {arches}; expected thin x86_64')
    checked += 1
if not checked:
    raise SystemExit(f'Media architecture validation failed: no Mach-O files in {root}')
print(f'Media architecture: {checked} Mach-O files are thin x86_64 ({root})')
PY
}

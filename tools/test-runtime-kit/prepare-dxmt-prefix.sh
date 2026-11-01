#!/bin/bash
# Prefix discovery support, not a game binary patch. Call only after verify_tree.
# Wine's normal PE search must find a winemetal.dll file in the prefix before
# its Unix builtin resolver can redirect it to the selected DXMT payload.
test_runtime_prepare_dxmt_prefix() {
  local engine="$1" prefix="$2" owner="$3" version="$4"
  local arch directory source destination parent physical temporary
  [[ -d "$owner" && ! -L "$owner" && -f "$owner/.cyder-test-version" &&
     "$(cat "$owner/.cyder-test-version")" == "$version" &&
     -f "$engine/version" && "$(cat "$engine/version")" == "$version" ]] || {
    echo 'DXMT prefix preparation: test runtime identity mismatch' >&2; return 1;
  }
  owner="$(cd "$owner" && pwd -P)"
  [[ ! -L "$owner/prefixes" && ! -L "$prefix" && -d "$prefix" ]] || {
    echo 'DXMT prefix preparation: missing or linked prefix' >&2; return 1;
  }
  prefix="$(cd "$prefix" && pwd -P)"
  [[ "$prefix" == "$owner/prefixes/"* ]] || {
    echo 'DXMT prefix preparation: prefix escapes test ownership' >&2; return 1;
  }
  # Preflight both architectures before copying either. Unknown existing DLLs
  # and links are never overwritten, even if they happen to have this name.
  for arch in x86_64 i386; do
    if [[ "$arch" == x86_64 ]]; then directory=system32; else directory=syswow64; fi
    source="$engine/lib/dxmt/$arch-windows/winemetal.dll"
    parent="$prefix/drive_c/windows/$directory"
    [[ -f "$source" && ! -L "$source" && -d "$parent" && ! -L "$parent" ]] || {
      echo "DXMT prefix preparation: missing or linked $arch component/directory" >&2; return 1;
    }
    physical="$(cd "$parent" && pwd -P)"
    [[ "$physical" == "$prefix/"* ]] || {
      echo 'DXMT prefix preparation: Windows directory escapes prefix' >&2; return 1;
    }
    destination="$parent/winemetal.dll"
    if [[ -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
      echo "DXMT prefix preparation: linked or non-file target $directory/winemetal.dll" >&2; return 1
    fi
    if [[ -e "$destination" ]] && ! cmp -s "$source" "$destination"; then
      echo "DXMT prefix preparation: existing $directory/winemetal.dll differs; use a fresh test bottle" >&2; return 1
    fi
  done
  for arch in x86_64 i386; do
    if [[ "$arch" == x86_64 ]]; then directory=system32; else directory=syswow64; fi
    source="$engine/lib/dxmt/$arch-windows/winemetal.dll"
    destination="$prefix/drive_c/windows/$directory/winemetal.dll"
    [[ ! -e "$destination" ]] || continue
    temporary="$(mktemp "$(dirname "$destination")/.cyder-winemetal.XXXXXX")" || return 1
    if ! cp "$source" "$temporary" || ! chmod 644 "$temporary"; then
      rm -f "$temporary"; return 1
    fi
    # Atomic no-clobber publication; a concurrent identical preparation is OK.
    if ! ln "$temporary" "$destination" 2>/dev/null; then
      rm -f "$temporary"
      [[ ! -L "$destination" ]] && cmp -s "$source" "$destination" || return 1
    else
      rm -f "$temporary"
    fi
  done
  echo 'DXMT prefix discovery: original x86_64/i386 winemetal.dll ready'
}

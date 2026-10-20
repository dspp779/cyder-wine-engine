#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import os
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
script = (root / 'scripts/build-wine.sh').read_text()
bootstrap = script[script.index('bootstrap_brew() {'):script.index('\nif [[ "$BOOTSTRAP_BREW"')]
with tempfile.TemporaryDirectory(prefix='cyder-bootstrap-') as tmp:
    base = pathlib.Path(tmp)
    prefix = base / 'prefix with spaces'
    log = base / 'calls'
    env = dict(os.environ, OGOM=str(base), HOMEBREW_PREFIX=str(prefix),
               HOMEBREW_REPOSITORY=str(prefix), HOMEBREW_CELLAR=str(prefix / 'Cellar'),
               CALLS=str(log), MACOSX_DEPLOYMENT_TARGET='10.15')
    helpers = r'''
run() { if [[ "$DRY_RUN" == 1 ]]; then printf '%s\n' "$*"; else "$@"; fi; }
git() {
  printf '%s\n' "$*" >> "$CALLS"
  [[ "$*" == "clone --depth 1 https://github.com/Homebrew/brew $HOMEBREW_PREFIX" ]] || return 90
  if [[ -n "${LOCAL_BREW_REPO:-}" ]]; then
    command git clone --depth 1 "$LOCAL_BREW_REPO" "$HOMEBREW_PREFIX"
    return
  fi
  mkdir -p "$HOMEBREW_PREFIX"
  if [[ "${FAIL_CLONE:-0}" == 1 ]]; then
    echo retained > "$HOMEBREW_PREFIX/partial"
    echo 'mock network failure' >&2
    return 42
  fi
  mkdir -p "$HOMEBREW_PREFIX/Library/Homebrew" "$HOMEBREW_PREFIX/bin" "$HOMEBREW_PREFIX/.git"
  touch "$HOMEBREW_PREFIX/Library/Homebrew/brew.sh" "$HOMEBREW_PREFIX/bin/brew"
  chmod +x "$HOMEBREW_PREFIX/bin/brew"
}
'''
    def boot(dry=False, fail=False):
        return subprocess.run(['bash', '-c', 'set -euo pipefail\n' +
            f'source "{root}/scripts/env-x86_64.sh"\n' +
            helpers + bootstrap + '\nbootstrap_brew'],
            env=dict(env, DRY_RUN=str(int(dry)), FAIL_CLONE=str(int(fail))),
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert boot(dry=True).returncode == 0 and not prefix.exists() and not log.exists()
    result = boot()
    assert result.returncode == 0, result.stdout
    assert boot().returncode == 0 and len(log.read_text().splitlines()) == 1
    # Each independent destination is isolated; never remove test subject data.
    for name, kind in [('empty', 'empty'), ('partial', 'partial'), ('stub', 'stub'),
                       ('failed', 'fail'), ('regular', 'file'), ('link', 'link'),
                       ('hidden', 'hidden')]:
        prefix = base / name
        env['HOMEBREW_PREFIX'] = str(prefix)
        env['HOMEBREW_REPOSITORY'] = str(prefix)
        env['HOMEBREW_CELLAR'] = str(prefix / 'Cellar')
        if kind == 'empty':
            prefix.mkdir()
        elif kind == 'partial':
            prefix.mkdir(); (prefix / 'keep').write_text('user data')
        elif kind == 'hidden':
            prefix.mkdir(); (prefix / '.keep').write_text('hidden data')
        elif kind == 'stub':
            (prefix / 'bin').mkdir(parents=True)
            (prefix / 'bin/brew').write_text('#!/bin/sh\nexit 99\n')
            (prefix / 'bin/brew').chmod(0o755)
        elif kind == 'file':
            prefix.write_text('user file')
        elif kind == 'link':
            prefix.symlink_to(base / 'missing')
        before = log.read_text()
        result = boot(fail=kind == 'fail')
        if kind == 'empty':
            assert result.returncode == 0, result.stdout
        elif kind == 'fail':
            assert result.returncode != 0 and 'mock network failure' in result.stdout
            assert 'preserved' in result.stdout and (prefix / 'partial').read_text().strip() == 'retained'
            after = log.read_text()
            assert boot().returncode != 0 and log.read_text() == after
        else:
            assert result.returncode != 0 and 'No data removed' in result.stdout, result.stdout
            assert log.read_text() == before
            assert boot(dry=True).returncode != 0 and log.read_text() == before
            if kind == 'partial': assert (prefix / 'keep').read_text() == 'user data'
            if kind == 'hidden': assert (prefix / '.keep').read_text() == 'hidden data'
            if kind == 'file': assert prefix.read_text() == 'user file'
            if kind == 'link': assert prefix.is_symlink()

    # Exercise real Git destination/clone behavior offline, including a nested
    # prefix that does not yet have a parent and an already empty destination.
    fixture = base / 'brew-source'
    (fixture / 'bin').mkdir(parents=True)
    (fixture / 'Library/Homebrew').mkdir(parents=True)
    (fixture / 'bin/brew').write_text('#!/bin/sh\nexit 0\n')
    (fixture / 'bin/brew').chmod(0o755)
    (fixture / 'Library/Homebrew/brew.sh').write_text('# fixture\n')
    def git_fixture(*args):
        subprocess.run(['git', '-C', str(fixture), *args], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    git_fixture('init', '-q')
    git_fixture('add', '.')
    git_fixture('-c', 'user.name=Bootstrap Test', '-c', 'user.email=test@example.invalid',
                '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Offline fixture')
    env['LOCAL_BREW_REPO'] = fixture.as_uri()
    for name in ('nested/new/prefix with spaces', 'real-empty'):
        prefix = base / name
        if name == 'real-empty': prefix.mkdir()
        env.update(HOMEBREW_PREFIX=str(prefix), HOMEBREW_REPOSITORY=str(prefix),
                   HOMEBREW_CELLAR=str(prefix / 'Cellar'))
        result = boot()
        assert result.returncode == 0, result.stdout
        head = subprocess.check_output(['git', '-C', str(prefix), 'rev-parse', '--show-toplevel'], text=True).strip()
        assert pathlib.Path(head).resolve() == prefix.resolve()
        after = log.read_text()
        assert boot().returncode == 0 and log.read_text() == after
    # A zero exit status without a usable Homebrew tree is still a failure.
    (fixture / 'Library/Homebrew/brew.sh').unlink()
    git_fixture('add', '-u')
    git_fixture('-c', 'user.name=Bootstrap Test', '-c', 'user.email=test@example.invalid',
                '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Incomplete fixture')
    prefix = base / 'incomplete-clone'
    env.update(HOMEBREW_PREFIX=str(prefix), HOMEBREW_REPOSITORY=str(prefix),
               HOMEBREW_CELLAR=str(prefix / 'Cellar'))
    result = boot()
    assert result.returncode != 0 and 'clone is incomplete' in result.stdout, result.stdout
    assert (prefix / '.git').is_dir() and (prefix / 'bin/brew').exists()
    env.pop('LOCAL_BREW_REPO')

    # Existing Intel Homebrew may keep its repository separate from the prefix.
    # Accept a complete explicit repository without cloning over either tree.
    prefix = base / 'split-prefix'
    repository = base / 'split-repository'
    (prefix / 'bin').mkdir(parents=True)
    (prefix / 'bin/brew').write_text('#!/bin/sh\nexit 0\n')
    (prefix / 'bin/brew').chmod(0o755)
    (repository / '.git').mkdir(parents=True)
    (repository / 'Library/Homebrew').mkdir(parents=True)
    (repository / 'Library/Homebrew/brew.sh').touch()
    env.update(HOMEBREW_PREFIX=str(prefix), HOMEBREW_REPOSITORY=str(repository),
               HOMEBREW_CELLAR=str(prefix / 'Cellar'))
    before = log.read_text()
    assert boot().returncode == 0 and log.read_text() == before
    prefix = base / 'new-split-prefix'
    env['HOMEBREW_PREFIX'] = str(prefix)
    result = boot()
    assert result.returncode != 0 and 'Cannot bootstrap with HOMEBREW_REPOSITORY=' in result.stdout
    assert not prefix.exists() and log.read_text() == before

    # Execute the production command arrays with a recorder instead of Wine/make.
    # Preserve argument boundaries so a compiler plus flags must remain one env value.
    start = script.index('# Bake -mmacosx-version-min')
    end = script.index('  if [[ "$DRY_RUN" -eq 1 ]]; then', start)
    commands = script[start:end] + '\nfi\n'
    recorder = r'''
run() { printf '%s\0' "$@" >> "$CALLS"; printf '\0' >> "$CALLS"; }
BUILD_PATH=/fake/mingw/bin:/fake/brew/bin:/usr/bin:/bin
HOMEBREW_PREFIX=/fake/brew
VULKAN_PKG_PC_PATH=/fake/brew/lib/pkgconfig
WINE_INSTALL=/fake/install
BUILD_TESTS=0
CONFIGURE_ONLY=0
JOBS=2
CONFIGURE_VULKAN_FLAG=(--without-vulkan)
'''
    for cc, objc, target in [(None, None, '10.15'), ('', '', '10.15'),
                             ('/custom/clang -arch x86_64', '/custom/objc -arch x86_64', '11.0'),
                             ('/custom/cc', None, '10.15'),
                             (None, '/custom/objc', '10.15')]:
        case_env = dict(env, MACOSX_DEPLOYMENT_TARGET=target)
        for key in ('CC', 'OBJC', 'CYDER_MACOSX_VERSION_MIN_FLAG', 'CFLAGS', 'OBJCFLAGS', 'LDFLAGS'):
            case_env.pop(key, None)
        if cc is not None: case_env['CC'] = cc
        if objc is not None: case_env['OBJC'] = objc
        log.write_bytes(b'')
        result = subprocess.run(['bash', '-c', 'set -euo pipefail\n' + recorder + commands],
                                env=case_env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert result.returncode == 0, result.stdout
        calls = [x.split(b'\0') for x in log.read_bytes().split(b'\0\0') if x]
        assert len(calls) == 3, calls
        for call in calls:
            args = [x.decode() for x in call]
            assert args[:3] == ['arch', '-x86_64', 'env']
            assert 'CC=' + (cc or '/usr/bin/clang -arch x86_64') in args
            assert 'OBJC=' + (objc or '/usr/bin/clang -arch x86_64') in args
            assert 'MACOSX_DEPLOYMENT_TARGET=' + target in args
            for key in ('CFLAGS', 'OBJCFLAGS', 'LDFLAGS'):
                assert any(x.startswith(key + '=') and '-mmacosx-version-min=' + target in x for x in args)
        assert b'../configure' in calls[0]
        assert calls[1][-2:] == [b'make', b'-j2']
        assert calls[2][-2:] == [b'make', b'install']
print('PASS test-build-bootstrap (offline bootstrap and configure/make/install compiler contracts)')
PY

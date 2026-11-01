#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
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
    log = base / 'calls'
    fixture = base / 'brew-source'
    fixture.mkdir()
    def git(*args):
        return subprocess.run(['git', *map(str, args)], check=True, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    def commit(repo):
        git('-C', repo, 'add', '.')
        git('-C', repo, '-c', 'user.name=Bootstrap Test', '-c', 'user.email=test@example.invalid',
            '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Offline fixture')
    def layout(repo):
        (repo / 'bin').mkdir(parents=True, exist_ok=True)
        (repo / 'Library/Homebrew').mkdir(parents=True, exist_ok=True)
        (repo / 'bin/brew').write_text('#!/bin/sh\nexit 0\n')
        (repo / 'bin/brew').chmod(0o755)
        (repo / 'Library/Homebrew/brew.sh').write_text('# fixture\n')
    layout(fixture)
    git('init', '-q', fixture)
    commit(fixture)
    prefix = base / 'prefix with spaces'
    env = dict(os.environ, OGOM=str(base), HOMEBREW_PREFIX=str(prefix),
               HOMEBREW_REPOSITORY=str(prefix), HOMEBREW_CELLAR=str(prefix / 'Cellar'),
               CALLS=str(log), MACOSX_DEPLOYMENT_TARGET='10.15', LOCAL_BREW_REPO=fixture.as_uri())
    for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE'):
        env.pop(key, None)
    helpers = r'''
run() { if [[ "$DRY_RUN" == 1 ]]; then printf '%s\n' "$*"; else "$@"; fi; }
git() {
  printf '%s\n' "$*" >> "$CALLS"
  [[ "$*" == "clone --depth 1 https://github.com/Homebrew/brew $HOMEBREW_PREFIX" ]] || return 90
  if [[ "${FAIL_CLONE:-0}" == 1 ]]; then
    mkdir -p "$HOMEBREW_PREFIX"
    echo retained > "$HOMEBREW_PREFIX/partial"
    echo 'mock network failure' >&2
    return 42
  fi
  command git clone --depth 1 "$LOCAL_BREW_REPO" "$HOMEBREW_PREFIX"
}
'''
    def set_prefix(name, repository=None):
        global prefix
        prefix = base / name
        env.update(HOMEBREW_PREFIX=str(prefix), HOMEBREW_REPOSITORY=str(repository or prefix),
                   HOMEBREW_CELLAR=str(prefix / 'Cellar'))
    def boot(dry=False, fail=False, extra=None):
        return subprocess.run(['bash', '-c', 'set -euo pipefail\n' +
            f'source "{root}/scripts/env-x86_64.sh"\n' + helpers + bootstrap + '\nbootstrap_brew'],
            env=dict(env, DRY_RUN=str(int(dry)), FAIL_CLONE=str(int(fail)), **(extra or {})),
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert boot(dry=True).returncode == 0 and not prefix.exists() and not log.exists()
    result = boot()
    assert result.returncode == 0, result.stdout
    assert boot().returncode == 0 and len(log.read_text().splitlines()) == 1
    # Valid repository roots must also work when Git redirect variables leak in.
    assert boot(extra={'GIT_DIR': str(base / 'missing'), 'GIT_WORK_TREE': str(base),
                       'GIT_COMMON_DIR': str(base / 'missing'), 'GIT_INDEX_FILE': str(base / 'missing')}).returncode == 0
    for name, kind in [('empty', 'empty'), ('partial', 'partial'), ('stub', 'stub'),
                       ('failed', 'fail'), ('regular', 'file'), ('link', 'link'),
                       ('hidden', 'hidden'), ('corrupt', 'corrupt'), ('unborn', 'unborn')]:
        set_prefix(name)
        if kind == 'empty': prefix.mkdir()
        elif kind == 'partial':
            prefix.mkdir(); (prefix / 'keep').write_text('user data')
        elif kind == 'hidden':
            prefix.mkdir(); (prefix / '.keep').write_text('hidden data')
        elif kind in ('stub', 'corrupt', 'unborn'):
            layout(prefix)
            if kind == 'corrupt': (prefix / '.git').mkdir()
            if kind == 'unborn': git('init', '-q', prefix)
        elif kind == 'file': prefix.write_text('user file')
        elif kind == 'link': prefix.symlink_to(base / 'missing')
        before = log.read_text()
        result = boot(fail=kind == 'fail')
        if kind == 'empty': assert result.returncode == 0, result.stdout
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
    # Regression: invalid .git must not be mistaken for the valid parent repo.
    parent = base / 'parent-repo'
    git('init', '-q', parent)
    (parent / 'keep').write_text('parent data'); commit(parent)
    set_prefix('parent-repo/brew')
    layout(prefix); (prefix / '.git').mkdir()
    assert pathlib.Path(git('-C', prefix, 'rev-parse', '--show-toplevel').stdout.strip()) == parent.resolve()
    result = boot()
    assert result.returncode != 0 and 'Invalid Homebrew Git repository' in result.stdout
    assert (parent / 'keep').read_text() == 'parent data'
    for name in ('nested/new/prefix with spaces', 'real-empty'):
        set_prefix(name)
        if name == 'real-empty': prefix.mkdir()
        result = boot(); assert result.returncode == 0, result.stdout
        assert pathlib.Path(git('-C', prefix, 'rev-parse', '--show-toplevel').stdout.strip()) == prefix.resolve()
    # Git worktrees and explicit split Intel prefixes remain supported.
    worktree = base / 'brew-worktree'
    git('-C', fixture, 'worktree', 'add', '-qb', 'test-worktree', worktree)
    set_prefix('brew-worktree'); assert boot().returncode == 0
    set_prefix('split-prefix', repository=fixture)
    (prefix / 'bin').mkdir(parents=True)
    (prefix / 'bin/brew').symlink_to(fixture / 'bin/brew')
    assert boot().returncode == 0
    set_prefix('new-split-prefix', repository=fixture)
    result = boot()
    assert result.returncode != 0 and 'Cannot bootstrap with HOMEBREW_REPOSITORY=' in result.stdout
    assert not prefix.exists()
    # A valid but unrelated repository must not conceal the prefix's bad Git
    # metadata (for example an inherited /opt/homebrew from the arm64 profile).
    set_prefix('corrupt', repository=fixture)
    result = boot()
    assert result.returncode != 0 and 'does not belong' in result.stdout, result.stdout
    profile = subprocess.run(['bash', '-c', f'source "{root}/scripts/env-x86_64.sh"; '
                              'printf "%s\\n" "$HOMEBREW_PREFIX" "$HOMEBREW_REPOSITORY" "$HOMEBREW_CELLAR"'],
                             env=dict(env, HOMEBREW_PREFIX='/opt/homebrew', HOMEBREW_REPOSITORY='/opt/homebrew',
                                      HOMEBREW_CELLAR='/opt/homebrew/Cellar'),
                             text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert profile.returncode == 0, profile.stderr
    assert profile.stdout.splitlines() == [str(base / '.brew-x86'), str(base / '.brew-x86'),
                                            str(base / '.brew-x86/Cellar')], profile.stdout

    # A successful clone with a missing runtime must still fail, preserving data.
    (fixture / 'Library/Homebrew/brew.sh').unlink(); git('-C', fixture, 'add', '-u'); commit(fixture)
    set_prefix('incomplete-clone')
    result = boot()
    assert result.returncode != 0 and 'clone is incomplete' in result.stdout, result.stdout
    assert (prefix / '.git').is_dir()

    # Execute the real --install-deps entry point with isolated preparer/brew
    # recorders. Invalid metadata must fail before any dependency installation.
    scripts = base / 'entry/scripts'; scripts.mkdir(parents=True)
    (scripts / 'build-wine.sh').write_text(script)
    (scripts / 'prepare-build-deps.sh').write_text('#!/bin/bash\nexit 0\n')
    (scripts / 'prepare-build-deps.sh').chmod(0o755)
    (scripts / 'env-x86_64.sh').write_text(
        f'source "{root}/scripts/env-x86_64.sh"\nSCRIPT_DIR="{scripts}"\n' +
        'brew_x86() { echo "BREW_INSTALL_REACHED"; exit 97; }\n')
    for name in ('stub', 'parent-repo/brew', 'unborn', 'missing-prefix', 'split-prefix'):
        set_prefix(name, repository=fixture if name == 'split-prefix' else None)
        result = subprocess.run(['bash', str(scripts / 'build-wine.sh'), '--install-deps',
                                 '--configure-only', '--without-vulkan'], env=env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if name == 'split-prefix':
            # The split fixture now lacks its runtime, so it too must fail closed.
            assert result.returncode != 0 and 'BREW_INSTALL_REACHED' not in result.stdout
        else:
            assert result.returncode != 0 and 'BREW_INSTALL_REACHED' not in result.stdout, result.stdout
    set_prefix('real-empty')
    result = subprocess.run(['bash', str(scripts / 'build-wine.sh'), '--install-deps'], env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert result.returncode == 97 and 'BREW_INSTALL_REACHED' in result.stdout, result.stdout

    # Media/graphics and manual callers share these helpers; they must not
    # bypass validation or write compiler wrappers into an invalid prefix.
    set_prefix('stub')
    for command in ('brew_x86 --version', 'brew_x86_install_runtime zlib'):
        result = subprocess.run(['bash', '-c', 'set -euo pipefail\n' +
                                 f'source "{root}/scripts/env-x86_64.sh"\n' + command],
                                env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert result.returncode != 0 and 'Incomplete Homebrew installation' in result.stdout, result.stdout
        assert not (prefix / 'opt').exists()

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
MAPLESTORY=0
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
PYTEST

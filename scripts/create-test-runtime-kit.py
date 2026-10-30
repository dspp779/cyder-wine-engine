#!/usr/bin/env python3
"""Assemble an isolated, ad-hoc test kit from project-produced archives.

Does not pack/sign Wine or install anything into a user's runtime. Those steps
remain owned by pack-engine-artifact.sh and the generated opt-in installer.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(archive, destination, root):
    if not hasattr(tarfile, 'data_filter'):
        raise RuntimeError('Python 3.12+ with safe tar extraction is required to build kits')
    with tarfile.open(archive) as stream:
        for entry in stream.getmembers():
            path = PurePosixPath(entry.name)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != root:
                raise ValueError('unsafe archive member: ' + entry.name)
            if not (entry.isdir() or entry.isfile() or entry.issym()):
                raise ValueError('unsupported archive member: ' + entry.name)
            if entry.issym():
                target = posixpath.normpath(posixpath.join(str(path.parent), entry.linkname))
                if entry.linkname.startswith('/') or not target.startswith(root + '/'):
                    raise ValueError('escaping archive symlink: ' + entry.name)
        stream.extractall(destination, filter='data')


def verify_sidecar(archive, sidecar):
    expected, name = sidecar.read_text().strip().split(None, 1)
    if name != archive.name or expected != digest(archive):
        raise ValueError('archive checksum mismatch: ' + archive.name)


def assemble(artifacts, output, zstd, commit, name, provenance, validation_report=None):
    if not re.fullmatch(r'[0-9a-f]{40}', commit) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', name):
        raise ValueError('safe test name and full source commit are required')
    if output.exists():
        raise ValueError('output exists; use a new kit directory')
    archives = list(artifacts.glob('engine-*.tar.xz'))
    if len(archives) != 1:
        raise ValueError('expected one project engine tar.xz')
    archive = archives[0]
    manifest_file = Path(str(archive) + '.manifest.json')
    manifest = json.loads(manifest_file.read_text())
    verify_sidecar(archive, Path(str(archive) + '.sha256'))
    if manifest.get('artifactSHA256') != digest(archive):
        raise ValueError('manifest archive checksum mismatch')
    required = {'cyder-winemac-gl-front-buffer-present.patch', 'wine-winemac-initialize-style-masks.patch', 'wine-win32u-full-client-visible-rect.patch'}
    if not required.issubset(manifest['patches']) or '-test-' not in manifest['versionLabel']:
        raise ValueError('a PR #2/#3 test manifest is required')
    source = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='cyder-kit-') as temporary:
        temp = Path(temporary)
        tree = temp / 'tree'
        tree.mkdir()
        extract(archive, tree, 'wine-x86_64')
        (tree / 'wine-x86_64').rename(tree / 'engine')
        core = tree / 'engine'
        if (core / 'version').read_text().strip() != manifest['versionLabel']:
            raise ValueError('embedded engine version mismatch')
        if digest(core / 'lib/wine/x86_64-windows/ntdll.dll') != manifest['ntdllSHA256']:
            raise ValueError('embedded NTDLL checksum mismatch')
        output.mkdir(parents=True)
        try:
            shutil.copy2(archive, output / archive.name)
            shutil.copy2(manifest_file, output / manifest_file.name)
            shutil.copytree(source / 'tools/test-runtime-kit', output, dirs_exist_ok=True)
            for document in output.glob('*.md'):
                document.write_text(document.read_text().replace('@TEST_VERSION@', manifest['versionLabel']).replace('@TEST_NAME@', name).replace('@SOURCE_COMMIT@', commit))
            (output / 'graphics').mkdir()
            config = dict(TEST_NAME=name, TEST_VERSION=manifest['versionLabel'], ENGINE_ARCHIVE=archive.name)
            for backend in ('dxvk', 'dxvk2', 'dxmt'):
                graphics = artifacts / 'graphics'
                expected, filename = (graphics / (backend + '-artifact-sha256.txt')).read_text().strip().split(None, 1)
                payload = graphics / filename
                if Path(filename).name != filename or digest(payload) != expected:
                    raise ValueError('graphics checksum mismatch: ' + backend)
                shutil.copy2(payload, output / 'graphics' / filename)
                config[backend.upper() + '_ARCHIVE'] = filename
                tar = temp / (backend + '.tar')
                with tar.open('wb') as stream:
                    subprocess.run([str(zstd), '-dc', str(payload)], stdout=stream, check=True)
                extract(tar, core / 'lib', backend)
            (output / 'bin').mkdir()
            shutil.copy2(zstd, output / 'bin/zstd')
            shutil.copy2(zstd.parent / 'LICENSE', output / 'bin/zstd-LICENSE')
            (output / 'kit-config.sh').write_text(''.join(key + '=' + shlex.quote(value) + '\n' for key, value in config.items()))
            regular = sorted(p for p in tree.rglob('*') if p.is_file() and not p.is_symlink())
            (output / 'installed-files.sha256').write_text(''.join(digest(p) + '  ' + p.relative_to(tree).as_posix() + '\n' for p in regular))
            (output / 'installed-links.tsv').write_text(''.join(p.relative_to(tree).as_posix() + '\t' + os.readlink(p) + '\n' for p in sorted(tree.rglob('*')) if p.is_symlink()))
            # Use the regression fixture already reviewed in the engine repo.
            (output / 'tests').mkdir()
            compiler_root = source / 'build/llvm-mingw-20260616-ucrt-macos-universal/bin'
            for target in ('x86_64', 'i686'):
                subprocess.run([str(compiler_root / (target + '-w64-mingw32-clang')), '-O2', '-Wall', '-Wextra', '-Werror', str(source / 'tests/fixtures/runtime-smoke.c'), '-lbcrypt', '-o', str(output / 'tests' / ('runtime-smoke-' + target + '.exe'))], check=True)
            subprocess.run([str(compiler_root / 'x86_64-w64-mingw32-clang'), '-O2', '-Wall', '-Wextra', '-Werror', str(source / 'tests/fixtures/d3d11-device-smoke.c'), '-ld3d11', '-o', str(output / 'tests/d3d11-device-smoke.exe')], check=True)
            info = dict(sourceCommit=commit, version=manifest['versionLabel'], channel='private-adhoc-test', engineArchive=archive.name, engineArchiveSHA256=digest(archive), graphics={key: value for key, value in config.items() if key.endswith('_ARCHIVE') and key != 'ENGINE_ARCHIVE'}, provenance=json.loads(provenance.read_text()))
            (output / 'build-info.json').write_text(json.dumps(info, indent=2, ensure_ascii=False) + '\n')
            if validation_report:
                shutil.copy2(validation_report, output / 'PACK-VALIDATION.md')
            packaged = sorted(p for p in output.rglob('*') if p.is_file())
            (output / 'package-files.sha256').write_text(''.join(digest(p) + '  ' + p.relative_to(output).as_posix() + '\n' for p in packaged))
            if digest(output / archive.name) != manifest['artifactSHA256']:
                raise ValueError('archive changed during assembly')
        except BaseException:
            shutil.rmtree(output)
            raise
    print('Created isolated test kit:', output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--zstd', type=Path, required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--provenance', type=Path, required=True)
    parser.add_argument('--validation-report', type=Path)
    options = parser.parse_args()
    assemble(options.artifacts.resolve(), options.output.resolve(), options.zstd.resolve(), options.source_commit, options.name, options.provenance, options.validation_report)

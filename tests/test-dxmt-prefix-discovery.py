#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'tools/test-runtime-kit/prepare-dxmt-prefix.sh'


class DXMTPrefixTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.owner = self.root / 'test-install'
        self.engine = self.owner / 'engine'
        self.prefix = self.owner / 'prefixes/fixture'
        self.version = 'fixture-test-dxmt'
        self.engine.mkdir(parents=True)
        (self.owner / '.cyder-test-version').write_text(self.version)
        (self.engine / 'version').write_text(self.version)
        for arch, directory in [('x86_64', 'system32'), ('i386', 'syswow64')]:
            source = self.engine / f'lib/dxmt/{arch}-windows/winemetal.dll'
            source.parent.mkdir(parents=True)
            source.write_bytes(b'original-' + arch.encode())
            (self.prefix / 'drive_c/windows' / directory).mkdir(parents=True)

    def tearDown(self):
        self.temp.cleanup()

    def prepare(self, prefix=None):
        return subprocess.run(['bash', '-c', 'set -euo pipefail; source "$1"; test_runtime_prepare_dxmt_prefix "$2" "$3" "$4" "$5"', 'test', str(HELPER), str(self.engine), str(prefix or self.prefix), str(self.owner), self.version], capture_output=True, text=True)

    def target(self, directory):
        return self.prefix / f'drive_c/windows/{directory}/winemetal.dll'

    def test_original_bytes_and_idempotence(self):
        self.assertEqual(self.prepare().returncode, 0)
        stats = []
        for arch, directory in [('x86_64', 'system32'), ('i386', 'syswow64')]:
            source = self.engine / f'lib/dxmt/{arch}-windows/winemetal.dll'
            dest = self.target(directory)
            self.assertEqual(source.read_bytes(), dest.read_bytes())
            stats.append((dest.stat().st_ino, dest.stat().st_mtime_ns))
        self.assertEqual(self.prepare().returncode, 0)
        self.assertEqual(stats, [(self.target(d).stat().st_ino, self.target(d).stat().st_mtime_ns) for d in ['system32', 'syswow64']])

    def test_missing_second_architecture_does_not_copy_first(self):
        (self.engine / 'lib/dxmt/i386-windows/winemetal.dll').unlink()
        self.assertNotEqual(self.prepare().returncode, 0)
        self.assertFalse(self.target('system32').exists())

    def test_unknown_existing_dll_preserved_and_preflight_is_atomic(self):
        self.target('syswow64').write_bytes(b'unknown existing DLL')
        self.assertNotEqual(self.prepare().returncode, 0)
        self.assertFalse(self.target('system32').exists())
        self.assertEqual(self.target('syswow64').read_bytes(), b'unknown existing DLL')

    def test_linked_target_refused(self):
        outside = self.root / 'outside'
        outside.write_bytes(b'preserve')
        self.target('system32').symlink_to(outside)
        self.assertNotEqual(self.prepare().returncode, 0)
        self.assertEqual(outside.read_bytes(), b'preserve')

    def test_external_and_linked_prefixes_refused(self):
        outside = self.root / 'outside-prefix'
        outside.mkdir()
        self.assertNotEqual(self.prepare(outside).returncode, 0)
        linked = self.owner / 'prefixes/linked'
        linked.symlink_to(self.prefix, target_is_directory=True)
        self.assertNotEqual(self.prepare(linked).returncode, 0)

    def test_windows_directory_escape_refused(self):
        directory = self.prefix / 'drive_c/windows/system32'
        directory.rmdir()
        outside = self.root / 'outside-windows'
        outside.mkdir()
        directory.symlink_to(outside, target_is_directory=True)
        self.assertNotEqual(self.prepare().returncode, 0)
        self.assertEqual(list(outside.iterdir()), [])

    def test_identity_mismatch_refused(self):
        (self.owner / '.cyder-test-version').write_text('another-version')
        self.assertNotEqual(self.prepare().returncode, 0)
        self.assertFalse(self.target('system32').exists())


if __name__ == '__main__':
    unittest.main()

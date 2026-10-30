#!/usr/bin/env python3
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('kit_builder', ROOT / 'scripts/create-test-runtime-kit.py')
kit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kit)


@unittest.skipUnless(hasattr(tarfile, "data_filter"), "test kit authoring requires Python 3.12+ safe tar extraction")
class KitSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def archive(self, name='wine-x86_64/file', link=None, hard=False):
        path = self.root / 'input.tar'
        with tarfile.open(path, 'w') as tar:
            entry = tarfile.TarInfo(name)
            if link is None:
                entry.size = 4
                tar.addfile(entry, io.BytesIO(b'data'))
            else:
                entry.type = tarfile.LNKTYPE if hard else tarfile.SYMTYPE
                entry.linkname = link
                tar.addfile(entry)
        return path

    def test_valid_archive(self):
        kit.extract(self.archive(), self.root / 'out', 'wine-x86_64')
        self.assertEqual((self.root / 'out/wine-x86_64/file').read_bytes(), b'data')

    def test_parent_and_absolute_members_refused(self):
        for name in ['wine-x86_64/../escape', '/absolute', 'other/file']:
            with self.assertRaises(ValueError):
                kit.extract(self.archive(name), self.root / 'out', 'wine-x86_64')
        self.assertFalse((self.root / 'out').exists())

    def test_escaping_symlinks_and_hardlinks_refused(self):
        for link, hard in [('../../escape', False), ('/absolute', False), ('wine-x86_64/file', True)]:
            with self.assertRaises(ValueError):
                kit.extract(self.archive(link=link, hard=hard), self.root / 'out', 'wine-x86_64')

    def test_valid_internal_symlink(self):
        kit.extract(self.archive('wine-x86_64/lib/alias', 'real'), self.root / 'out', 'wine-x86_64')
        self.assertEqual(os.readlink(self.root / 'out/wine-x86_64/lib/alias'), 'real')

    def test_checksum_and_sidecar_name(self):
        path = self.root / 'archive'
        path.write_bytes(b'original')
        sidecar = self.root / 'sha256'
        sidecar.write_text(kit.digest(path) + '  archive\n')
        kit.verify_sidecar(path, sidecar)
        path.write_bytes(b'changed')
        with self.assertRaises(ValueError):
            kit.verify_sidecar(path, sidecar)
        sidecar.write_text(kit.digest(path) + '  another-name\n')
        with self.assertRaises(ValueError):
            kit.verify_sidecar(path, sidecar)

    def template(self):
        import shutil
        folder = self.root / 'scripts'
        shutil.copytree(ROOT / 'tools/test-runtime-kit', folder)
        (folder / 'kit-config.sh').write_text('TEST_NAME=fixture\nTEST_VERSION=fixture-test\n')
        return folder

    def test_production_and_linked_roots_refused(self):
        folder = self.template()
        linked = self.root / 'linked'
        linked.symlink_to(self.root, target_is_directory=True)
        for target in ['relative', '/', str(Path.home()), str(Path.home() / '.cyder/runtime'), str(Path.home() / 'Library/Application Support/Cyder'), str(linked)]:
            result = subprocess.run(['bash', str(folder / 'common.sh')], env=dict(os.environ, CYDER_TEST_ROOT=target), capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, target)

    def test_invalid_backend_and_bottle_refused_before_launch(self):
        folder = self.template()
        for args in [['--backend', 'unknown'], ['--bottle', '../real'], ['--bottle', '/absolute']]:
            result = subprocess.run(['bash', str(folder / 'Run Test.command'), '--dry-run'] + args,
                                    env=dict(os.environ, CYDER_TEST_ROOT=str(self.root / 'absent')),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((self.root / 'absent').exists())


if __name__ == '__main__':
    unittest.main()

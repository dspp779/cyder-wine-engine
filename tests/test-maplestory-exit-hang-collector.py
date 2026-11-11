import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('collector', Path(__file__).resolve().parents[1] /
                                            'tools/collect-maplestory-exit-hang.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class CaptureTests(unittest.TestCase):
    def attempt(self, identities=None, name=b'/games/MapleStory.exe\n', fail=False):
        calls = []
        values = iter(identities) if identities else None

        def execute(command):
            calls.append(command)
            data = name if command[-1] == 'comm=' else b'evidence\n'
            return subprocess.CompletedProcess(command, int(fail and command[0].endswith('sample')), data)

        with tempfile.TemporaryDirectory() as root:
            out = Path(root) / 'capture'
            try:
                collector.capture(123, out, lambda _: next(values) if values else (123, 501, 1, 2),
                                  execute, lambda _: None)
            finally:
                self.calls = calls
                self.manifest = (out / 'manifest.json').read_text() if out.exists() else ''

    def test_two_samples_and_no_process_arguments_or_mutations(self):
        self.attempt()
        self.assertEqual(sum(c[0] == '/usr/bin/sample' for c in self.calls), 2)
        self.assertTrue(all(c[0] in ['/bin/ps', '/usr/bin/sample', '/usr/bin/vmmap'] for c in self.calls))
        self.assertNotIn('args', repr(self.calls))
        self.assertTrue(all('-c' in c for c in self.calls if '-M' in c))
        self.assertIn('"status": "captured"', self.manifest)

    def test_wrong_executable(self):
        with self.assertRaisesRegex(RuntimeError, 'not MapleStory'):
            self.attempt(name=b'/games/Other.exe\n')
        self.assertEqual(len(self.calls), 1)

    def test_pid_reuse(self):
        with self.assertRaisesRegex(RuntimeError, 'identity changed'):
            self.attempt(identities=[(123, 501, 1, 2), (123, 501, 3, 4)])
        self.assertEqual(len(self.calls), 1)
        self.assertIn('incomplete', self.manifest)

    def test_exit_during_capture(self):
        with self.assertRaisesRegex(RuntimeError, 'exited or changed'):
            self.attempt(identities=[(123, 501, 1, 2)] * 2 + [(123, 501, 3, 4)])
        self.assertEqual(len(self.calls), 2)

    def test_capture_failure(self):
        with self.assertRaisesRegex(RuntimeError, 'Capture failed'):
            self.attempt(fail=True)
        self.assertIn('incomplete', self.manifest)


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Offline gate tests. Mock signatures are never production acceptance evidence."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('pe_signing', ROOT / 'scripts/pe-signing.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


def pe(machine=0x8664):
    data = bytearray(1024)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 128)
    data[128:132] = b'PE\0\0'
    size = 224 if machine == 0x14c else 240
    struct.pack_into('<HHIIIHH', data, 132, machine, 1, 0, 0, 0, size, 0x2102)
    opt = 152
    struct.pack_into('<H', data, opt, 0x10b if machine == 0x14c else 0x20b)
    struct.pack_into('<I', data, opt + 4, 512)
    struct.pack_into('<I', data, opt + 16, 4096)
    struct.pack_into('<II', data, opt + 32, 4096, 512)
    struct.pack_into('<II', data, opt + 56, 8192, 512)
    struct.pack_into('<H', data, opt + 68, 3)
    struct.pack_into('<I', data, opt + (92 if machine == 0x14c else 108), 16)
    section = opt + size
    data[section:section + 8] = b'.text\0\0\0'
    struct.pack_into('<IIII', data, section + 8, 1, 4096, 512, 512)
    struct.pack_into('<I', data, section + 36, 0x60000020)
    data[512] = 0xc3
    return bytes(data)


def fake_signed(data):
    info = p.pe_info(data)
    result = bytearray(data)
    result.extend(b'\0' * (-len(result) % 8))
    offset = len(result)
    struct.pack_into('<II', result, info['certificateEntry'], offset, 16)
    struct.pack_into('<I', result, info['checksum'], 12345)
    result.extend(struct.pack('<IHH', 16, 0x200, 2) + b'fixture!')
    return bytes(result)


class GateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cyder-pe-gate-')
        self.base = Path(self.temp.name)
        self.source = self.base / 'original'
        self.stage = self.base / 'stage'
        self.source.mkdir()
        entries = []
        self.a = 'lib/wine/i386-windows/bcrypt.dll'
        self.b = 'lib/wine/x86_64-windows/bcrypt.dll'
        self.c = 'lib/wine/x86_64-windows/upstream.dll'
        self.d = 'lib/wine/i386-windows/metadata.tlb'
        for name, data, action in [(self.a, pe(0x14c), 'sign'), (self.b, pe(), 'sign'),
                                   (self.c, fake_signed(pe()), 'preserve'), (self.d, pe(0x14c), 'unsigned-exception')]:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            entries.append({'path': name, 'sha256': p.digest(data), 'action': action,
                            'ownership': 'cyder-built' if action == 'sign' else 'upstream',
                            'certificateSHA256': 'b' * 64, 'reason': 'Reviewed metadata-only PE fixture'})
        shutil.copytree(self.source, self.stage)
        self.policy = {'schemaVersion': 1, 'signingCertificateSHA256': 'a' * 64,
                       'timestampURL': 'https://tsa.example.test', 'files': entries}
        self.policy_path = self.base / 'policy.json'
        self.write_policy()
        for name in ['signer', 'verify', 'ca', 'tsa-ca']:
            path = self.base / name
            path.write_text('fixture')
            path.chmod(0o700)
        self.environment = patch.dict(os.environ, {
            'CYDER_PE_SIGNER': str(self.base / 'signer'), 'CYDER_PE_VERIFY_TOOL': str(self.base / 'verify'),
            'CYDER_PE_CA_FILE': str(self.base / 'ca'), 'CYDER_PE_TSA_CA_FILE': str(self.base / 'tsa-ca')})
        self.environment.start()
        self.calls = []
        self.good_timestamp = True
        self.mutate = False
        self.command = patch.object(p, 'invoke', self.invoke)
        self.command.start()

    def tearDown(self):
        self.command.stop()
        self.environment.stop()
        self.temp.cleanup()

    def write_policy(self):
        self.policy_path.write_text(json.dumps(self.policy))

    def invoke(self, args):
        self.calls.append(args)
        if args[0] == str(self.base / 'signer'):
            before = Path(args[args.index('--input') + 1]).read_bytes()
            after = bytearray(fake_signed(before))
            if self.mutate:
                after[512] ^= 1
            Path(args[args.index('--output') + 1]).write_bytes(after)
            return ''
        return ('Timestamp Server Signature verification: ok\n' if self.good_timestamp else '') + 'Signature verification: ok\n'

    def prepare(self):
        return p.prepare(self.stage, self.policy_path)

    def test_sign_only_reviewed_staging_preserve_upstream_and_exceptions(self):
        source = {n: x['sha256'] for n, x in p.inventory(self.source).items()}
        result = self.prepare()
        self.assertEqual(source, {n: x['sha256'] for n, x in p.inventory(self.source).items()})
        sign_calls = [a for a in self.calls if '--output' in a]
        self.assertEqual(2, len(sign_calls))
        self.assertTrue(all(str(self.stage) in a[a.index('--input') + 1] for a in sign_calls))
        for name in (self.c, self.d):
            self.assertEqual((self.source / name).read_bytes(), (self.stage / name).read_bytes())
        self.assertEqual(4, len(result['files']))
        self.assertEqual(result, p.verify(self.stage, self.policy_path))
        self.assertEqual(p.unsigned_payload((self.source / self.a).read_bytes()), p.unsigned_payload((self.stage / self.a).read_bytes()))

    def test_unknown_input_stops_before_any_signing(self):
        (self.stage / self.b).write_bytes(pe() + b'changed')
        with self.assertRaises(p.SigningError): self.prepare()
        self.assertFalse(any('--output' in a for a in self.calls))

    def test_cannot_resign_existing_upstream_or_accept_unreviewed_ownership(self):
        self.policy['files'][2]['action'] = 'sign'
        self.policy['files'][2]['ownership'] = 'cyder-built'
        self.write_policy()
        with self.assertRaises(p.SigningError): self.prepare()
        self.policy['files'][0]['ownership'] = 'unknown'
        with self.assertRaises(p.SigningError): p.policy_rows(self.policy)

    def test_policy_paths_duplicates_and_unreviewed_actions(self):
        for change in [{'path': '../escape'}, {'path': self.b}, {'action': 'review-required'}, {'sha256': 'bad'}]:
            policy = copy.deepcopy(self.policy)
            policy['files'][0].update(change)
            with self.assertRaises(p.SigningError): p.policy_rows(policy)

    def test_certificate_timestamp_and_trust_configuration_required(self):
        for key in ['signingCertificateSHA256', 'timestampURL']:
            policy = copy.deepcopy(self.policy)
            policy[key] = ''
            with self.assertRaises(p.SigningError): p.preflight(policy)
        for key in ['CYDER_PE_SIGNER', 'CYDER_PE_VERIFY_TOOL', 'CYDER_PE_CA_FILE', 'CYDER_PE_TSA_CA_FILE']:
            with patch.dict(os.environ, {key: ''}):
                with self.assertRaises(p.SigningError): p.preflight(self.policy)
        self.good_timestamp = False
        with self.assertRaises(p.SigningError): self.prepare()

    def test_verification_pin_and_no_insecure_fallbacks(self):
        self.prepare()
        calls = [a for a in self.calls if 'verify' in a]
        self.assertTrue(calls)
        for a in calls:
            self.assertNotIn('-ignore-crl', a)
            self.assertNotIn('-ignore-timestamp', a)
            pin = a[a.index('-require-leaf-hash') + 1]
            self.assertIn(pin, ['sha256:' + 'a' * 64, 'sha256:' + 'b' * 64])
            self.assertIn('-TSA-CAfile', a)

    def test_signer_must_not_change_executable_bytes(self):
        self.mutate = True
        with self.assertRaises(p.SigningError): self.prepare()
        self.assertFalse((self.stage / p.PROVENANCE).exists())

    def test_provider_failure_and_timeout_redact_output(self):
        self.command.stop()
        for error in [subprocess.CompletedProcess([], 1, b'SECRET-provider-output'), subprocess.TimeoutExpired([], 1)]:
            target = patch.object(p.subprocess, 'run', side_effect=error) if isinstance(error, Exception) else patch.object(p.subprocess, 'run', return_value=error)
            with target:
                with self.assertRaises(p.SigningError) as caught: p.invoke(['provider'])
                self.assertNotIn('SECRET', str(caught.exception))
        self.command.start()

    def test_archive_roundtrip_revalidates_without_signing(self):
        self.prepare()
        archive = self.base / 'engine.tar'
        with tarfile.open(archive, 'w') as tar: tar.add(self.stage, arcname='wine-x86_64')
        out = self.base / 'unpacked'
        with tarfile.open(archive) as tar: tar.extractall(out, filter='data')
        self.calls.clear()
        p.verify(out / 'wine-x86_64', self.policy_path)
        self.assertFalse(any('--output' in a for a in self.calls))
        (out / 'wine-x86_64' / self.b).unlink()
        with self.assertRaises(p.SigningError): p.verify(out / 'wine-x86_64', self.policy_path)

    def test_policy_or_provenance_or_unsigned_exception_tamper(self):
        self.prepare()
        (self.stage / self.d).write_bytes(pe(0x14c) + b'changed')
        with self.assertRaises(p.SigningError): p.verify(self.stage, self.policy_path)
        (self.stage / self.d).write_bytes(pe(0x14c))
        self.policy_path.write_text(self.policy_path.read_text() + ' ')
        with self.assertRaises(p.SigningError): p.verify(self.stage, self.policy_path)

    def test_unknown_extra_file_and_symlink_are_not_followed(self):
        extra = self.stage / 'lib/wine/i386-windows/extra.dll'
        extra.write_bytes(pe(0x14c))
        with self.assertRaises(p.SigningError): self.prepare()
        extra.unlink()
        extra.symlink_to(self.source / self.a)
        with self.assertRaises(p.SigningError): self.prepare()

    def test_architecture_and_malformed_certificate_fail_closed(self):
        (self.stage / self.a).write_bytes(pe())
        with self.assertRaises(p.SigningError): p.inventory(self.stage)
        data = bytearray(fake_signed(pe()))
        info = p.pe_info(data)
        struct.pack_into('<I', data, info['certificateEntry'], len(data) + 100)
        with self.assertRaises(p.SigningError): p.pe_info(data)

    def test_existing_provenance_never_reused_for_prepare(self):
        self.prepare()
        self.calls.clear()
        with self.assertRaises(p.SigningError): self.prepare()
        self.assertEqual([], self.calls)

    def test_strip_preserves_signed_pe_with_debug_sections(self):
        (self.stage / 'bin').mkdir()
        wine = self.stage / 'bin/wine'; wine.write_text('#!/bin/sh\n'); wine.chmod(0o700)
        tools = self.base / 'tools'; tools.mkdir()
        strip = tools / 'llvm-strip'
        strip.write_text('#!/bin/sh\nprintf changed >> "$2"\n'); strip.chmod(0o700)
        objdump = tools / 'llvm-objdump'
        objdump.write_text('#!/bin/sh\necho " 7 .debug_info 00000100"\n'); objdump.chmod(0o700)
        before = (self.stage / self.c).read_bytes()
        result = subprocess.run(['bash', str(ROOT / 'scripts/strip-wine-install.sh'), str(self.stage)],
                                env=dict(os.environ, CYDER_LLVM_STRIP=str(strip)), capture_output=True)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(before, (self.stage / self.c).read_bytes())
        self.assertNotEqual((self.source / self.a).read_bytes(), (self.stage / self.a).read_bytes())

    def test_default_strip_skips_linked_files_and_directories_without_following(self):
        (self.stage / 'bin').mkdir()
        wine = self.stage / 'bin/wine'
        wine.write_text('#!/bin/sh\n'); wine.chmod(0o700)
        outside = self.base / 'outside'
        outside.mkdir()
        fifo = outside / 'blocked.dll'; os.mkfifo(fifo)
        source = self.stage / 'lib/wine/i386-windows'
        (source / 'alias.dll').symlink_to(fifo)
        (source / 'linked-directory').symlink_to(outside, target_is_directory=True)
        tools = self.base / 'tools'; tools.mkdir()
        strip = tools / 'llvm-strip'
        strip.write_text('#!/bin/sh\nprintf changed >> "$2"\n'); strip.chmod(0o700)
        objdump = tools / 'llvm-objdump'
        objdump.write_text('#!/bin/sh\necho " 7 .debug_info 00000100"\n'); objdump.chmod(0o700)
        result = subprocess.run(['bash', str(ROOT / 'scripts/strip-wine-install.sh'), str(self.stage)],
                                env=dict(os.environ, CYDER_LLVM_STRIP=str(strip)), capture_output=True, timeout=5)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertTrue((source / 'alias.dll').is_symlink())
        self.assertTrue((source / 'linked-directory').is_symlink())
        # Opt-in signing still requires a concrete reviewed tree and rejects aliases.
        with self.assertRaises(p.SigningError): p.inventory(self.stage)

    def test_real_crypto_rejects_missing_timestamp_and_wrong_leaf(self):
        tool = os.environ.get('CYDER_TEST_OSSLSIGNCODE')
        openssl = os.environ.get('CYDER_TEST_OPENSSL')
        if not tool or not openssl:
            self.skipTest('optional real offline crypto: provide existing test osslsigncode/OpenSSL paths')
        self.command.stop()
        cert, key = self.base / 'fixture.crt', self.base / 'fixture.key'
        subprocess.run([openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(key),
                        '-out', str(cert), '-days', '1', '-subj', '/CN=Cyder Offline TEST ONLY',
                        '-addext', 'extendedKeyUsage=codeSigning'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        output = self.base / 'signed.dll'
        subprocess.run([tool, 'sign', '-certs', str(cert), '-key', str(key), '-h', 'sha256', '-in',
                        str(self.source / self.b), '-out', str(output)], check=True, stdout=subprocess.DEVNULL)
        der = subprocess.run([openssl, 'x509', '-in', str(cert), '-outform', 'DER'], check=True, capture_output=True).stdout
        pin = p.digest(der)
        check = subprocess.run([tool, 'verify', '-CAfile', str(cert), '-require-leaf-hash', 'sha256:' + pin,
                                '-in', str(output)], capture_output=True)
        self.assertEqual(0, check.returncode, check.stdout)
        self.assertEqual(p.unsigned_payload((self.source / self.b).read_bytes()), p.unsigned_payload(output.read_bytes()))
        settings = {'CYDER_PE_VERIFY_TOOL': tool, 'CYDER_PE_CA_FILE': str(cert), 'CYDER_PE_TSA_CA_FILE': str(cert)}
        with self.assertRaisesRegex(p.SigningError, 'timestamp'): p.verify_signature(output, pin, settings)
        with self.assertRaises(p.SigningError): p.verify_signature(output, '0' * 64, settings)
        self.command.start()


if __name__ == '__main__':
    unittest.main()

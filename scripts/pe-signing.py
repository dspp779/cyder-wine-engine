#!/usr/bin/env python3
"""PE Authenticode release gate. Operates on a pack-owned staging tree only.

No private keys or passwords are accepted here. A release-machine signer adapter
owns hardware/cloud authentication and receives input/output paths plus TSA URL.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys
import tempfile
from urllib.parse import urlparse

PROVENANCE = 'cyder-pe-provenance.json'
ARCHES = {'i386-windows': 0x14c, 'x86_64-windows': 0x8664}
HEX = re.compile(r'^[0-9a-f]{64}$')


class SigningError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise SigningError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    require(path.is_file() and path.stat().st_size <= 8 * 1024 * 1024, 'missing/oversized signing metadata')
    return json.loads(path.read_bytes())


def pe_info(data):
    if data[:2] != b'MZ':
        return None
    require(len(data) >= 64, 'truncated DOS header')
    offset = struct.unpack_from('<I', data, 60)[0]
    if data[offset:offset + 4] != b'PE\0\0':
        return None  # DOS/NE images are outside this PE policy.
    require(offset + 24 <= len(data), 'truncated PE header')
    machine, optional_size = struct.unpack_from('<H', data, offset + 4)[0], struct.unpack_from('<H', data, offset + 20)[0]
    optional = offset + 24
    require(optional_size >= 2 and optional + optional_size <= len(data), 'truncated optional header')
    magic = struct.unpack_from('<H', data, optional)[0]
    require(magic in (0x10b, 0x20b), 'unsupported PE optional header')
    directory = optional + (112 if magic == 0x20b else 96)
    require(directory + 40 <= optional + optional_size, 'missing certificate directory')
    certificate_entry = directory + 32
    certificate, size = struct.unpack_from('<II', data, certificate_entry)
    require((certificate == 0) == (size == 0), 'invalid certificate directory')
    if size:
        require(certificate % 8 == 0 and size >= 8 and certificate >= optional + optional_size and
                certificate + size == len(data), 'unsupported/truncated certificate table')
    return {'machine': machine, 'checksum': optional + 64, 'certificateEntry': certificate_entry,
            'certificateOffset': certificate, 'certificateSize': size}


def unsigned_payload(data):
    """Signing may change checksum/security directory and append aligned certificates only."""
    info = pe_info(data)
    require(info is not None, 'expected PE')
    body = bytearray(data[:info['certificateOffset']] if info['certificateSize'] else data)
    body[info['checksum']:info['checksum'] + 4] = b'\0' * 4
    body[info['certificateEntry']:info['certificateEntry'] + 8] = b'\0' * 8
    body.extend(b'\0' * (-len(body) % 8))
    return bytes(body)


def inventory(root):
    root = root.resolve(strict=True)
    rows = {}
    for arch, machine in ARCHES.items():
        directory = root / 'lib/wine' / arch
        for parent in (root / 'lib', root / 'lib/wine', directory):
            require(parent.is_dir() and not parent.is_symlink(), 'linked/missing Wine PE directory')
        # Inspect recursively so unexpected nested PEs cannot bypass classification.
        for path in sorted(directory.rglob('*')):
            require(not path.is_symlink(), 'symlink in Wine PE tree')
            if path.is_dir():
                continue
            require(stat.S_ISREG(path.stat().st_mode), 'special file in Wine PE tree')
            data = path.read_bytes()
            info = pe_info(data)
            if info:
                require(info['machine'] == machine, 'PE architecture/path mismatch')
                relative = path.relative_to(root).as_posix()
                rows[relative] = {'path': relative, 'sha256': digest(data), 'size': len(data),
                                  'architecture': arch, 'signed': bool(info['certificateSize'])}
    require(rows and all(any(r['architecture'] == arch for r in rows.values()) for arch in ARCHES),
            'empty/incomplete two-architecture PE inventory')
    return rows


def policy_rows(policy):
    require(policy.get('schemaVersion') == 1, 'unsupported PE signing policy')
    require(HEX.fullmatch(policy.get('signingCertificateSHA256', '')) is not None, 'missing signing certificate SHA-256 pin')
    url = urlparse(policy.get('timestampURL', ''))
    require(url.scheme == 'https' and url.hostname and not url.username and not url.password and not url.fragment,
            'timestamp URL must be HTTPS without credentials')
    entries = policy.get('files')
    require(isinstance(entries, list) and 0 < len(entries) <= 20000, 'missing reviewed PE policy entries')
    rows = {}
    for entry in entries:
        path = entry['path']
        require(isinstance(path, str) and not any(ord(c) < 32 for c in path) and '\\' not in path and
                all(p not in ('', '.', '..') for p in path.split('/')) and
                any(path.startswith('lib/wine/' + arch + '/') for arch in ARCHES), 'unsafe PE policy path')
        require(path not in rows and HEX.fullmatch(entry.get('sha256', '')) is not None, 'duplicate path/invalid source digest')
        action = entry.get('action')
        require(action in ('sign', 'preserve', 'unsigned-exception'), 'unreviewed PE signing action')
        if action == 'sign':
            require(entry.get('ownership') == 'cyder-built', 'only reviewed Cyder-built PE may be signed')
        elif action == 'preserve':
            require(HEX.fullmatch(entry.get('certificateSHA256', '')) is not None, 'missing upstream certificate pin')
        else:
            require(isinstance(entry.get('reason'), str) and len(entry['reason'].strip()) >= 12,
                    'unsigned exception needs a specific review reason')
        rows[path] = entry
    return rows


def config():
    result = {}
    for key in ('CYDER_PE_VERIFY_TOOL', 'CYDER_PE_CA_FILE', 'CYDER_PE_TSA_CA_FILE'):
        value = os.environ.get(key, '')
        require(value and Path(value).is_absolute() and Path(value).is_file(), 'configure ' + key)
        if key.endswith('_TOOL'):
            require(os.access(value, os.X_OK), 'verifier is not executable')
        result[key] = value
    return result


def invoke(args):
    # Never print signer output: provider diagnostics can contain authentication data.
    try:
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SigningError('signing/verification command unavailable or timed out') from error
    require(result.returncode == 0, 'signing/verification failed (provider output withheld)')
    return result.stdout.decode('utf-8', 'replace')


def verify_signature(path, certificate, settings):
    # No ignore-crl, ignore-timestamp, network/chain fallback, or untrusted leaf acceptance.
    text = invoke([settings['CYDER_PE_VERIFY_TOOL'], 'verify', '-CAfile', settings['CYDER_PE_CA_FILE'],
                   '-TSA-CAfile', settings['CYDER_PE_TSA_CA_FILE'], '-require-leaf-hash', 'sha256:' + certificate,
                   '-in', str(path)])
    require(re.search(r'^Timestamp Server Signature verification: ok\s*$', text, re.M) is not None,
            'verified Authenticode timestamp required')
    require(re.search(r'^Signature verification: ok\s*$', text, re.M) is not None,
            'verified Authenticode signature required')


def preflight(policy):
    policy_rows(policy)
    settings = config()
    signer = os.environ.get('CYDER_PE_SIGNER', '')
    require(signer and Path(signer).is_absolute() and Path(signer).is_file() and os.access(signer, os.X_OK),
            'configure CYDER_PE_SIGNER executable adapter')
    return settings, signer


def prepare(root, policy_path):
    root = root.resolve(strict=True)
    policy = read_json(policy_path)
    entries = policy_rows(policy)
    policy_digest = digest(policy_path.read_bytes())
    settings, signer = preflight(policy)
    require(not (root / PROVENANCE).exists(), 'staging already has PE provenance; use a fresh staging tree')
    actual = inventory(root)
    require(set(actual) == set(entries), 'PE inventory differs from reviewed policy')
    # Validate every input before invoking a signer, including upstream signatures.
    for name, row in actual.items():
        entry = entries[name]
        require(row['sha256'] == entry['sha256'], 'unreviewed PE input: ' + name)
        require(row['signed'] == (entry['action'] == 'preserve'), 'input signature/action conflict: ' + name)
        if entry['action'] == 'preserve':
            verify_signature(root / name, entry['certificateSHA256'], settings)
    records = []
    for name, row in actual.items():
        entry, path = entries[name], root / name
        before = path.read_bytes()
        require(digest(before) == row['sha256'], 'PE input changed during signing')
        if entry['action'] == 'sign':
            # Output is a separate file. Never give a provider an original/install path.
            with tempfile.TemporaryDirectory(prefix='.pe-sign-', dir=root) as temp:
                output = Path(temp) / 'signed.pe'
                invoke([signer, '--input', str(path), '--output', str(output), '--timestamp-url', policy['timestampURL']])
                require(output.is_file() and not output.is_symlink(), 'signer did not produce a regular PE')
                after = output.read_bytes()
                require(pe_info(after)['certificateSize'] > 0 and unsigned_payload(before) == unsigned_payload(after),
                        'signer changed PE executable content')
                verify_signature(output, policy['signingCertificateSHA256'], settings)
                require(path.read_bytes() == before, 'signer modified input in place')
                output.chmod(path.stat().st_mode & 0o777)
                # Break staging hardlinks; a signature must not affect a sibling path.
                os.replace(output, path)
        after = path.read_bytes()
        records.append({'path': name, 'action': entry['action'], 'sourceSHA256': row['sha256'],
                        'sha256': digest(after), 'size': len(after)})
    require(digest(policy_path.read_bytes()) == policy_digest, 'policy changed during signing')
    result = {'schemaVersion': 1, 'policySHA256': policy_digest, 'files': records}
    (root / PROVENANCE).write_text(json.dumps(result, indent=2) + '\n')
    verify(root, policy_path)
    return result


def verify(root, policy_path):
    root = root.resolve(strict=True)
    policy = read_json(policy_path)
    entries = policy_rows(policy)
    settings = config()
    metadata = root / PROVENANCE
    require(not metadata.is_symlink(), 'linked PE provenance')
    provenance = read_json(metadata)
    require(provenance.get('schemaVersion') == 1 and provenance.get('policySHA256') == digest(policy_path.read_bytes()),
            'PE provenance policy mismatch')
    records = provenance['files']
    recorded = {r['path']: r for r in records}
    actual = inventory(root)
    require(len(records) == len(recorded) and set(recorded) == set(entries) == set(actual), 'PE inventory/provenance mismatch')
    for name, row in actual.items():
        entry, record = entries[name], recorded[name]
        require(record['sourceSHA256'] == entry['sha256'] and record['action'] == entry['action'] and
                record['sha256'] == row['sha256'] and record['size'] == row['size'], 'PE content/provenance mismatch')
        if entry['action'] == 'unsigned-exception':
            require(not row['signed'] and row['sha256'] == entry['sha256'], 'unsigned exception changed')
        else:
            require(row['signed'], 'missing PE signature')
            pin = policy['signingCertificateSHA256'] if entry['action'] == 'sign' else entry['certificateSHA256']
            if entry['action'] == 'preserve':
                require(row['sha256'] == entry['sha256'], 'upstream signed PE was changed')
            verify_signature(root / name, pin, settings)
    return provenance


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('inventory', 'preflight', 'prepare', 'verify', 'strip-candidates'))
    parser.add_argument('--root', type=Path)
    parser.add_argument('--policy', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        if args.action == 'strip-candidates':
            require(args.root is not None, 'strip candidates need --root')
            candidates = []
            for directory in sorted((args.root / 'lib/wine').glob('*-windows')):
                if directory.is_symlink():
                    continue  # Match find -type f: never traverse a linked PE tree.
                for path in sorted(directory.rglob('*')):
                    if path.is_symlink():
                        continue  # Preserve aliases; never strip their external targets.
                    if path.is_dir():
                        continue
                    require(path.is_file(), 'special PE strip input')
                    info = pe_info(path.read_bytes())
                    if not info or not info['certificateSize']:
                        candidates.append(path)
            for path in candidates:
                sys.stdout.buffer.write(os.fsencode(path) + b'\0')
            return 0
        if args.action == 'inventory':
            require(args.root is not None and args.output is not None, 'inventory needs --root and --output')
            entries = [dict(row, action='review-required', ownership='unreviewed') for row in inventory(args.root).values()]
            result = {'schemaVersion': 1, 'signingCertificateSHA256': '', 'timestampURL': '', 'files': entries}
            require(not args.output.exists(), 'inventory refuses to overwrite a review file')
            args.output.write_text(json.dumps(result, indent=2) + '\n')
        else:
            require(args.policy is not None, 'reviewed --policy required')
            if args.action == 'preflight':
                preflight(read_json(args.policy))
            else:
                require(args.root is not None, '--root required')
                (prepare if args.action == 'prepare' else verify)(args.root, args.policy)
        print('PE Authenticode ' + args.action + ': OK')
    except (SigningError, OSError, ValueError, KeyError, TypeError, struct.error):
        # Keep paths and provider credentials out of public build logs.
        print('PE Authenticode gate failed: check reviewed policy, input digests, signer, trust chain, timestamp and revocation access.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

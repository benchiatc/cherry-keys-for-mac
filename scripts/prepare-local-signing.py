#!/usr/bin/env python3
"""Create/reuse an isolated local code-signing identity; never change trust settings."""
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

os.umask(0o077)
directory = Path.home() / 'Library/Application Support/CherryKeysMac/Signing'
directory.mkdir(parents=True, exist_ok=True, mode=0o700)
directory.chmod(0o700)
metadata = directory / 'identity.json'
if metadata.exists():
    print('Reusing existing local signing identity:', json.loads(metadata.read_text())['sha1'])
    raise SystemExit(0)
keychain = directory / 'CherryKeys.keychain-db'
if keychain.exists():
    raise SystemExit('An incomplete signing keychain already exists; preserve and inspect it before retrying.')
password = secrets.token_urlsafe(40)
password_file = directory / 'keychain-password'
password_file.write_text(password)
previous_search_list = subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True)
import shlex
previous_paths = shlex.split(previous_search_list)

def run(args):
    result = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        # Some commands receive the isolated keychain's password as an argument.
        # Never let CalledProcessError print that argument list.
        raise SystemExit(f'{args[0]} {args[1]} failed (exit {result.returncode}). '+result.stderr.replace(password, '[redacted]'))

try:
    run(['security', 'create-keychain', '-p', password, str(keychain)])
    run(['security', 'set-keychain-settings', '-lut', '21600', str(keychain)])
    run(['security', 'unlock-keychain', '-p', password, str(keychain)])
    with tempfile.TemporaryDirectory(prefix='prepare-', dir=directory) as tmp:
        root = Path(tmp)
        config = root / 'certificate.cnf'
        config.write_text('''[req]
prompt = no
distinguished_name = name
x509_extensions = signing
[name]
CN = Cherry Keys Local Development
O = Local Development
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
''')
        private_key, certificate, archive = root/'key.pem', root/'certificate.pem', root/'identity.p12'
        # No private key or password is written inside the source tree or app.
        subprocess.run(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:3072', '-nodes',
                        '-days', '3650', '-config', str(config), '-keyout', str(private_key),
                        '-out', str(certificate)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        run(['openssl', 'pkcs12', '-export', '-inkey', str(private_key), '-in', str(certificate),
             '-out', str(archive), '-passout', 'file:'+str(password_file),
             '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1'])
        run(['security', 'import', str(archive), '-k', str(keychain), '-P', password, '-T', '/usr/bin/codesign'])
        run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain)])
        der = subprocess.check_output(['openssl', 'x509', '-in', str(certificate), '-outform', 'DER'])
        (directory/'certificate.der').write_bytes(der)
        sha1 = hashlib.sha1(der).hexdigest().upper()
        metadata.write_text(json.dumps({'sha1': sha1, 'sha256': hashlib.sha256(der).hexdigest(),
                                        'name': 'Cherry Keys Local Development'}, indent=2)+'\n')
finally:
    # security create-keychain may append a search entry. Preserve the user's
    # original search list; builds name this isolated keychain explicitly.
    run(['security', 'list-keychains', '-d', 'user', '-s', *previous_paths])
print('Prepared local signing identity:', sha1)
print('No certificate trust settings or default keychain were changed.')

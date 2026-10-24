#!/usr/bin/env python3
"""Sign with the isolated identity, restoring the keychain search list afterward."""
import fcntl
import json
from pathlib import Path
import shlex
import signal
import subprocess
import sys

if len(sys.argv) != 3:
    raise SystemExit('Usage: sign-local.py <identifier> <executable-or-app>')
directory = Path.home() / 'Library/Application Support/CherryKeysMac/Signing'
identity = json.loads((directory / 'identity.json').read_text())['sha1']
keychain = str(directory / 'CherryKeys.keychain-db')
password = (directory / 'keychain-password').read_text()

def run(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        # Never include the command/arguments: security receives a password.
        raise RuntimeError(result.stderr.replace(password, '[redacted]').strip() or 'Signing command failed')
    return result.stdout

# Serialize our own signing operations so their temporary search-list changes
# cannot overwrite each other. The default keychain and trust policy are untouched.
with (directory / 'signing.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    previous = shlex.split(run(['security', 'list-keychains', '-d', 'user']))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    try:
        run(['security', 'unlock-keychain', '-p', password, keychain])
        # Older macOS codesign versions also consult the search list while
        # resolving a private key, even with an explicit --keychain argument.
        run(['security', 'list-keychains', '-d', 'user', '-s', keychain,
             *[path for path in previous if path != keychain]])
        run(['codesign', '--force', '--sign', identity, '--keychain', keychain,
             '--options', 'runtime', '--timestamp=none', '--identifier', sys.argv[1], sys.argv[2]])
    except RuntimeError as error:
        raise SystemExit(str(error)) from None
    finally:
        run(['security', 'list-keychains', '-d', 'user', '-s', *previous])

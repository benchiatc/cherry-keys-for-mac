#!/usr/bin/env python3
"""Audit the explicit public-source allowlist. Does not inspect private settings."""
import getpass
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOP = {'README.md', 'CHANGELOG.md', 'LICENSE', 'CONTRIBUTING.md', '.gitignore', '.swift-format'}
DIRECTORIES = ('Sources', 'Tests', 'scripts', 'Resources', 'docs', '.github')

def public_files():
    for name in sorted(TOP):
        path = ROOT / name
        if path.is_file():
            yield path
    for name in DIRECTORIES:
        for path in sorted((ROOT / name).rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc':
                yield path

def audit():
    problems = []
    username = getpass.getuser()
    patterns = [r'/' + r'Users' + r'/[^/\s"\']+', r'(?i)(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}',
                r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----']
    for path in public_files():
        relative = path.relative_to(ROOT)
        if path.is_symlink():
            problems.append(f'{relative}: symlinks are not allowed')
            continue
        if path.suffix in {'.png', '.icns'}:
            continue
        if path.suffix in {'.p12', '.pfx', '.pem', '.key', '.msi', '.cab'}:
            problems.append(f'{relative}: excluded file type')
            continue
        try:
            data = path.read_text()
        except UnicodeError:
            problems.append(f'{relative}: unexpected binary')
            continue
        if any(re.search(pattern, data) for pattern in patterns):
            problems.append(f'{relative}: possible private identifier or credential')
        if username.casefold() not in {'root', 'runner', 'admin', 'user', 'test'} and len(username) > 3 and username.casefold() in data.casefold():
            problems.append(f'{relative}: local account name found')
    if problems:
        raise SystemExit('\n'.join(problems))
    print('PASS: public-source allowlist contains no detected local paths, account name, device addresses or private keys.')

if __name__ == '__main__':
    audit()

#!/usr/bin/env python3
"""Reject inconsistent release docs, staged app metadata or local distribution files."""
import argparse
import hashlib
import importlib.util
import plistlib
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEYS = ('CFBundleShortVersionString', 'CFBundleVersion', 'LSMinimumSystemVersion')


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, help='Check a staged or installed app bundle.')
    parser.add_argument('--dist', action='store_true', help='Check local archives and checksums.')
    args = parser.parse_args()
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    version, build, minimum = (info[key] for key in KEYS)
    require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version), 'Invalid release version.')
    require(re.fullmatch(r'[1-9][0-9]*', build), 'Invalid build number.')
    readme = (ROOT / 'README.md').read_text()
    require(f'Current preview: **v{version} (build {build})**' in readme,
            'README current preview does not match Info.plist.')
    require(f'/releases/tag/v{version})' in readme,
            'README release page does not match Info.plist.')
    require(f"macOS {minimum.removesuffix('.0')} or later" in readme,
            'README minimum macOS does not match Info.plist.')
    image = f'CherryKeysMac-{version}-macOS-universal.dmg'
    downloads = re.findall(r'https://[^\s)]+/releases/download/v[^\s)]+\.dmg', readme)
    require(downloads and all(url.endswith(f'/v{version}/{image}') for url in downloads),
            'README DMG download does not match Info.plist.')
    changelog = (ROOT / 'CHANGELOG.md').read_text()
    first = re.search(r'^## (.+)$', changelog, re.MULTILINE)
    require(first and first[1].startswith(f'{version} (build {build}) — '),
            'Latest changelog entry does not match Info.plist.')
    if args.app:
        staged = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
        require(all(staged.get(key) == info[key] for key in KEYS),
                'Staged app version/build/minimum macOS differs from source. Rebuild first.')
    if args.dist:
        for folder, filename in (('app', image), ('source', 'CherryKeysMac-source.zip')):
            directory = ROOT / 'dist' / folder
            lines = (directory / 'SHA256SUMS').read_text().splitlines()
            expected = hashlib.sha256((directory / filename).read_bytes()).hexdigest()
            require(lines == [f'{expected}  {filename}'], f'{folder} checksum manifest is stale.')
        spec = importlib.util.spec_from_file_location('public', ROOT / 'scripts/check-public-source.py')
        public = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(public)
        files = {f'CherryKeysMac/{p.relative_to(ROOT)}': p for p in public.public_files()}
        with zipfile.ZipFile(ROOT / 'dist/source/CherryKeysMac-source.zip') as archive:
            names = archive.namelist()
            require(len(names) == len(set(names)) and set(names) == set(files),
                    'Source ZIP inventory differs from the public-source allowlist.')
            require(all(archive.read(name) == path.read_bytes() for name, path in files.items()),
                    'Source ZIP contents are stale. Export source again.')
    print(f'PASS: v{version} build {build} release metadata' +
          (' and local distribution files' if args.dist else '') + ' are consistent.')


if __name__ == '__main__':
    main()

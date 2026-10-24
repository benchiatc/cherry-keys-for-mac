#!/usr/bin/env python3
"""Create a reviewed, source-only archive; never include parent Git history."""
import hashlib
import zipfile
from pathlib import Path
from importlib.util import spec_from_file_location, module_from_spec

root = Path(__file__).resolve().parent.parent
spec = spec_from_file_location('public_source', root / 'scripts/check-public-source.py')
public = module_from_spec(spec)
spec.loader.exec_module(public)
public.audit()
output = root / 'dist/source/CherryKeysMac-source.zip'
output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in public.public_files():
        archive.write(path, str(Path('CherryKeysMac') / path.relative_to(root)))
digest = hashlib.sha256(output.read_bytes()).hexdigest()
(output.parent / 'SHA256SUMS').write_text(f'{digest}  {output.name}\n')
print(f'Created dist/source/{output.name}: {digest}')

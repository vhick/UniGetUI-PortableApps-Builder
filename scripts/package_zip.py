#!/usr/bin/env python3
"""Independent, deterministic-ish PortableApps ZIP assembly and full read-back."""
from pathlib import Path
import sys, zipfile, hashlib

if len(sys.argv) != 3:
    raise SystemExit('usage: package_zip.py <stage/UniGetUIPortable> <dist/output.zip>')
source, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
if source.name != 'UniGetUIPortable' or not (source/'UniGetUIPortable.exe').is_file():
    raise SystemExit('wrong source root or missing genuine launcher')
if output.is_relative_to(source) or output.exists():
    raise SystemExit('ZIP output inside source or already exists')
output.parent.mkdir(parents=True, exist_ok=True)
items = sorted(source.rglob('*'))
for item in items:
    if item.is_symlink():
        raise SystemExit(f'reparse/symlink forbidden: {item}')
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as z:
    z.writestr(source.name+'/', b'')
    for p in items:
        arc = source.name+'/'+p.relative_to(source).as_posix()
        if p.is_dir():
            z.writestr(arc+'/', b'')
        else:
            z.write(p, arc)
with zipfile.ZipFile(output, 'r') as z:
    if z.testzip() is not None:
        raise SystemExit('ZIP CRC error')
    files = set(z.namelist())
    required = {
        'UniGetUIPortable/UniGetUIPortable.exe',
        'UniGetUIPortable/App/UniGetUI/UniGetUI.exe',
        'UniGetUIPortable/App/AppInfo/appinfo.ini',
        'UniGetUIPortable/App/AppInfo/appicon.ico',
        'UniGetUIPortable/Data/',
        'UniGetUIPortable/Other/Source/Build-Manifest.json',
    }
    if not required.issubset(files):
        raise SystemExit('ZIP missing required entries: '+str(required-files))
    if any(n.startswith('/') or '..' in n.split('/') for n in files):
        raise SystemExit('unsafe ZIP traversal path')
    if any(n.startswith('UniGetUIPortable/Data/') and n != 'UniGetUIPortable/Data/' for n in files):
        raise SystemExit('release unexpectedly packages user Data')
print('VALIDATED:', output.name, output.stat().st_size, 'bytes SHA-256', hashlib.sha256(output.read_bytes()).hexdigest())

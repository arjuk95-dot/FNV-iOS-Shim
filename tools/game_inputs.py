#!/usr/bin/env python3
"""Package locally generated inputs, or validate them in an approved private build."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

PIN = 'ff8e0d791e3e1f0148a2245c12c7706855e66926'


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(4 << 20), b''):
            h.update(block)
    return h.hexdigest()


def allowed(name):
    return name in ('FalloutNV.exe','diagnostic-fixtures.json') or bool(re.fullmatch(r'generated/(?:table|stubs|tu_[0-9a-fA-F]+)\.c', name))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    pack = sub.add_parser('pack')
    pack.add_argument('--exe', type=Path, required=True)
    pack.add_argument('--generated', type=Path, required=True)
    pack.add_argument('--out', type=Path, required=True)
    pack.add_argument('--fixtures', type=Path, help='optional small diagnostic caller-state manifest; no game assets')
    pack.add_argument('--generator',type=Path,help='record the maintained emitter identity used for this source set')
    unpack = sub.add_parser('unpack')
    unpack.add_argument('archive', type=Path)
    unpack.add_argument('destination', type=Path)
    unpack.add_argument('--archive-sha256', required=True)
    unpack.add_argument('--exe-sha256', required=True)
    args = parser.parse_args()
    if args.command == 'pack':
        paths = [args.generated / 'table.c', args.generated / 'stubs.c', *sorted(args.generated.glob('tu_*.c'))]
        if len(paths) < 3 or not all(path.is_file() for path in paths):
            raise ValueError('Complete generated source set required')
        sources = {'FalloutNV.exe': args.exe, **{f'generated/{path.name}': path for path in paths}}
        if args.fixtures:
            if args.fixtures.stat().st_size>65536:raise ValueError('Diagnostic fixtures exceed bound')
            sources['diagnostic-fixtures.json']=args.fixtures
        if not all(allowed(name) for name in sources):
            raise ValueError('Unexpected generated source filename')
        manifest = dict(recompiler_commit=PIN, files={name: dict(bytes=path.stat().st_size, sha256=sha(path))
                                                    for name, path in sources.items()})
        if args.generator:
            manifest['generator']={'emitter_sha256':sha(args.generator),'flag_analysis_sha256':sha(args.generator.with_name('flaglive.py'))}
        args.out.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.out, 'x', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for name, path in sources.items():
                archive.write(path, name)
            archive.writestr('input-manifest.json', json.dumps(manifest, indent=2))
        print(json.dumps(dict(archive=str(args.out.resolve()), sha256=sha(args.out),
                              bytes=args.out.stat().st_size, input_files=len(sources),
                              uncompressed_bytes=sum(item['bytes'] for item in manifest['files'].values()),
                              executable_sha256=manifest['files']['FalloutNV.exe']['sha256']), indent=2))
    else:
        if sha(args.archive) != args.archive_sha256:
            raise ValueError('Input ZIP digest mismatch')
        if args.destination.exists():
            raise ValueError('Extraction destination must be new')
        with zipfile.ZipFile(args.archive) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)) or not all(allowed(name) or name == 'input-manifest.json' for name in names):
                raise ValueError('Unexpected or duplicate ZIP member')
            manifest = json.loads(archive.read('input-manifest.json'))
            if manifest['recompiler_commit'] != PIN or set(names) != set(manifest['files']) | {'input-manifest.json'}:
                raise ValueError('Manifest mismatch')
            if not {'FalloutNV.exe', 'generated/table.c', 'generated/stubs.c'} <= set(names) or not any(name.startswith('generated/tu_') for name in names):
                raise ValueError('Generated input set incomplete')
            if manifest['files']['FalloutNV.exe']['sha256'] != args.exe_sha256:
                raise ValueError('Executable identity mismatch')
            if sum(archive.getinfo(name).file_size for name in names) > 12 * 1024**3:
                raise ValueError('Unexpected input size')
            for name, expected in manifest['files'].items():
                member = archive.getinfo(name)
                if member.file_size != expected['bytes']:
                    raise ValueError(f'Size mismatch: {name}')
                destination = args.destination / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                h = hashlib.sha256()
                with archive.open(member) as source, destination.open('xb') as target:
                    for block in iter(lambda: source.read(4 << 20), b''):
                        h.update(block)
                        target.write(block)
                if h.hexdigest() != expected['sha256']:
                    raise ValueError(f'Digest mismatch: {name}')
            (args.destination / 'input-manifest.json').write_text(json.dumps(manifest, indent=2))
        print(f'Validated {len(manifest["files"])} private build inputs; no Data, P-code or saves included')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Build a native macOS startup diagnostic; never package it as an iPhone app."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
R = ROOT / 'upstream/recomp'
H = R / 'host'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generated', type=Path)
    parser.add_argument('--host-check', action='store_true')
    parser.add_argument('--discovery-prefix', type=Path, help='optional installed Unicorn prefix for a separate Mac discovery binary')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--cache', type=Path, help='private, verified object cache for this compiler/SDK/header configuration')
    args = parser.parse_args()
    if not args.host_check and not (args.generated and (args.generated/'table.c').is_file()
                                   and (args.generated/'stubs.c').is_file()):
        parser.error('Provide a complete --generated directory or use --host-check')
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    cc = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--find', 'clang'], text=True).strip()
    sources = [ROOT/'tools/startup/main.c', ROOT/'ios/FNVPad.c', R/'rt_dispatch.c', H/'dshow.m']
    sources += sorted(H.glob('*.c'))  # includes the null renderer; no UIKit or Metal window
    if not args.host_check:
        sources += [args.generated/'table.c', args.generated/'stubs.c', *sorted(args.generated.glob('tu_*.c'))]
    args.out.mkdir(parents=True, exist_ok=True)
    binary = args.out/'fnv-startup'
    cache=args.cache
    old_manifest={}
    if cache:
        cache.mkdir(parents=True,exist_ok=True)
        if (cache/'manifest.json').is_file():
            old_manifest=json.loads((cache/'manifest.json').read_text())
    with tempfile.TemporaryDirectory(dir=args.out) as temp:
        tmp = Path(temp)
        base = [cc, '-isysroot', sdk, '-O1', '-DRT_CALLTRACE', '-I', str(R), '-I', str(H), '-I', str(ROOT/'ios')]
        if args.host_check:
            base.append('-DFNV_STARTUP_HOST_CHECK')
        signature=hashlib.sha256(json.dumps(base).encode()+subprocess.check_output([cc,'--version']))
        for directory in [R,H,ROOT/'ios']:
            for header in sorted(directory.glob('*.h')):
                signature.update(str(header.relative_to(ROOT)).encode()+header.read_bytes())
        config=signature.digest()
        def compile_one(item):
            index, source = item
            key=hashlib.sha256(config+source.name.encode()+source.read_bytes()).hexdigest()
            stored=cache/(key+'.o') if cache else None
            if stored and stored.is_file() and hashlib.sha256(stored.read_bytes()).hexdigest()==old_manifest.get(stored.name):
                return source, str(stored), True
            obj=tmp/f'{index}.o'
            subprocess.run(base + (['-fobjc-arc'] if source.suffix == '.m' else [])
                           + ['-c', str(source), '-o', str(obj)], check=True)
            if stored:
                os.replace(obj,stored)
                obj=stored
            return source, str(obj), False
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            compiled = list(pool.map(compile_one, enumerate(sources)))
        objects=[obj for _,obj,_ in compiled]
        if cache:
            manifest={Path(obj).name:hashlib.sha256(Path(obj).read_bytes()).hexdigest() for _,obj,_ in compiled}
            (cache/'manifest.json').write_text(json.dumps(manifest,indent=2))
        print(f'Native objects: {sum(reused for _,_,reused in compiled)} reused, {sum(not reused for _,_,reused in compiled)} compiled',flush=True)
        frameworks = ['Foundation', 'AVFoundation', 'CoreGraphics', 'CoreMedia', 'CoreVideo', 'ImageIO', 'UniformTypeIdentifiers']
        link = [cc, '-isysroot', sdk, *objects, *[v for f in frameworks for v in ('-framework', f)],
                '-Wl,-stack_size,0x1000000']
        subprocess.run([*link, '-o', str(binary)], check=True)
        if args.discovery_prefix:
            prefix = args.discovery_prefix.resolve()
            assert (prefix/'include/unicorn/unicorn.h').is_file(), 'Unicorn C headers missing'
            fallback = tmp/'discovery.o'
            subprocess.run([*base, '-I', str(prefix/'include'), '-c', str(ROOT/'tools/startup/FallbackDiscovery.c'),
                            '-o', str(fallback)], check=True)
            subprocess.run([*link, str(fallback), '-L', str(prefix/'lib'), '-lunicorn',
                            '-Wl,-rpath,' + str(prefix/'lib'), '-o', str(args.out/'fnv-discovery')], check=True)
    print(binary.resolve())

if __name__ == '__main__':
    main()

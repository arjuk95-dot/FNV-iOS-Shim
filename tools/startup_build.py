#!/usr/bin/env python3
"""Build a native macOS startup diagnostic; never package it as an iPhone app."""
import argparse
import concurrent.futures
import hashlib
import json
import os
import re
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
    parser.add_argument('--trace-entries', default='', help='comma-separated selected guest entry addresses for read-only state probes')
    parser.add_argument('--trace-returns', default='', help='comma-separated selected callees for read-only post-return probes')
    parser.add_argument('--reference-files-commit',help='build a separate historical filesystem reference, retaining current translated game objects')
    args = parser.parse_args()
    trace_entries={int(value,0) for value in args.trace_entries.split(',') if value.strip()}
    trace_returns={int(value,0) for value in args.trace_returns.split(',') if value.strip()}
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
            content=source.read_bytes()
            transformed=False
            if trace_entries and args.generated and source.parent.resolve()==args.generated.resolve():
                def probe(match):
                    nonlocal transformed
                    entry=int(match.group(1),16)
                    if entry not in trace_entries:return match.group(0)
                    transformed=True
                    return match.group(0)+f'rt_diag_entry(c,0x{entry:x}u);'.encode()
                content=re.sub(rb'RT_ENTER\(0x([0-9a-f]+)u\);',probe,content)
                if transformed:
                    content=content.replace(b'#include "rt.h"',b'#include "rt.h"\nvoid rt_diag_entry(CPU *,uint32_t);',1)
            if trace_returns and args.generated and source.parent.resolve()==args.generated.resolve():
                site=0;returned=False
                def returned_call(match):
                    nonlocal site,returned
                    if match.group(1):
                        site=int(match.group(1),16);return match.group(0)
                    callee=int(match.group(2),16)
                    if callee not in trace_returns:return match.group(0)
                    returned=True
                    return match.group(0)+f'rt_diag_return(c,0x{site:x}u,0x{callee:x}u);'.encode()
                content=re.sub(rb'L_([0-9a-f]+):|g_([0-9a-f]+)\(c\);',returned_call,content)
                if returned:
                    transformed=True
                    content=content.replace(b'#include "rt.h"',b'#include "rt.h"\nvoid rt_diag_return(CPU *,uint32_t,uint32_t);',1)
            key=hashlib.sha256(config+source.name.encode()+content).hexdigest()
            stored=cache/(key+'.o') if cache else None
            if stored and stored.is_file() and hashlib.sha256(stored.read_bytes()).hexdigest()==old_manifest.get(stored.name):
                return source, str(stored), True
            obj=tmp/f'{index}.o'
            compiled_source=source
            if transformed:
                compiled_source=tmp/('probe-'+source.name)
                compiled_source.write_bytes(content)
            subprocess.run(base + (['-fobjc-arc'] if source.suffix == '.m' else [])
                           + ['-c', str(compiled_source), '-o', str(obj)], check=True)
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
        if args.reference_files_commit:
            if not re.fullmatch('[0-9a-f]{40}',args.reference_files_commit):raise ValueError('Reference must be an exact commit')
            reference=tmp/'file-shims-reference.c';reference.write_bytes(subprocess.check_output(
                ['git','show',args.reference_files_commit+':upstream/recomp/host/shims_files.c'],cwd=ROOT))
            ref_object=tmp/'file-shims-reference.o'
            subprocess.run([*base,'-c',str(reference),'-o',str(ref_object)],check=True)
            ref_objects=[str(ref_object) if source==H/'shims_files.c' else obj for source,obj,_ in compiled]
            subprocess.run([cc,'-isysroot',sdk,*ref_objects,*[v for f in frameworks for v in ('-framework',f)],
                            '-Wl,-stack_size,0x1000000','-o',str(args.out/'fnv-file-reference')],check=True)
        if args.generated:
            runtime=tmp/'differential-runtime.o'
            subprocess.run([*base,'-c',str(ROOT/'tools/differential/rt_test.c'),'-o',str(runtime)],check=True)
            test_objects=[obj for source,obj,_ in compiled if source==R/'rt_dispatch.c'
                          or source.parent.resolve()==args.generated.resolve()]
            subprocess.run([cc,'-isysroot',sdk,'-dynamiclib',*test_objects,str(runtime),
                            '-o',str(args.out/'libfnv-differential.dylib')],check=True)
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

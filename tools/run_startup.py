#!/usr/bin/env python3
"""Run the strict dispatcher before a phone build, recording its precise stop.

No Data is uploaded by this diagnostic. Reaching a missing-data boundary is not
proof of title-screen boot or gameplay; a translation trap always fails the run.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('exe', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=60)
    parser.add_argument('--label', choices=['strict', 'discovery','synthetic','synthetic-discovery','synthetic-bsa','synthetic-bsa-discovery','synthetic-bsa-raw','synthetic-bsa-raw-discovery'], default='strict')
    args = parser.parse_args()
    binary, exe = args.binary.resolve(), args.exe.resolve()
    fixture=None
    if args.label.startswith('synthetic'):
        # Author-created minimal input exercises the real XML loader, not a fake
        # successful return. No original game asset or owner INI is uploaded.
        fixture=tempfile.TemporaryDirectory(prefix='fnv-synthetic-ui-')
        directory=Path(fixture.name);shutil.copyfile(exe,directory/exe.name);exe=directory/exe.name
        from startup.synthetic_assets import prepare
        prepare(directory,packed='bsa' in args.label,compressed='raw' not in args.label)
    args.out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, FNV_ROOT=str(exe.parent), FNV_TRACE_FILES='1', FNV_QUIT_AFTER='1', FNV_FALLBACK_TRACE='1')
    log = args.out/f'{args.label}-startup.log'
    timed_out = False
    with log.open('wb') as stream:
        try:
            result = subprocess.run([str(binary), str(exe)], cwd=exe.parent, env=env,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=args.timeout)
            code = result.returncode
        except subprocess.TimeoutExpired:
            timed_out, code = True, None
    text = log.read_text(errors='replace')
    traps = re.findall(r'\[host\] TRAP[^\n]*', text)
    receipt = dict(returncode=code, timed_out=timed_out, translation_traps=traps,
                   executable_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(),
                   log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(),
                   mode=args.label, game_data_supplied=False, synthetic_ui_fixture=fixture is not None,title_or_gameplay_verified=False)
    roots = exe.parent/'fallback_entries.txt'
    if args.label.endswith('discovery') and roots.is_file():
        entries = sorted({int(line, 0) for line in roots.read_text().splitlines() if line.strip()})
        (args.out/'fallback_entries.txt').write_text(''.join(f'{entry:#x}\n' for entry in entries))
        receipt['fallback_entries'] = [f'{entry:#x}' for entry in entries]
    if args.label.endswith('discovery'):
        for evidence in exe.parent.glob('fallback-*'):
            if evidence.is_file() and evidence.suffix in ('.bin','.jsonl','.json'):
                (args.out/evidence.name).write_bytes(evidence.read_bytes())
    (args.out/f'{args.label}-startup-result.json').write_text(json.dumps(receipt, indent=2))
    print(json.dumps(receipt, indent=2))
    print(text[-10000:])
    if fixture:fixture.cleanup()
    if traps or timed_out or code != 0:
        raise SystemExit(1)

if __name__ == '__main__':
    main()

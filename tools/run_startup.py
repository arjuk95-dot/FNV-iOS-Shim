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
import subprocess

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('exe', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=60)
    args = parser.parse_args()
    binary, exe = args.binary.resolve(), args.exe.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, FNV_ROOT=str(exe.parent), FNV_TRACE_FILES='1', FNV_QUIT_AFTER='1')
    log = args.out/'startup.log'
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
                   game_data_supplied=False, title_or_gameplay_verified=False)
    (args.out/'startup-result.json').write_text(json.dumps(receipt, indent=2))
    print(json.dumps(receipt, indent=2))
    print(text[-10000:])
    if traps or timed_out or code != 0:
        raise SystemExit(1)

if __name__ == '__main__':
    main()

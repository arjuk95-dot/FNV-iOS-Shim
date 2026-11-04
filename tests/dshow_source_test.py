"""Exercise the production graph using an authored standard IAsyncReader source."""
import argparse, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / 'upstream/recomp/host'
parser = argparse.ArgumentParser()
parser.add_argument('--reference', action='store_true')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='fnv-dshow-') as temp:
    work = Path(temp)
    binary = work / 'dshow-source-test'
    flags = []
    if args.reference:
        old = work / 'dshow.m'
        old.write_bytes(subprocess.check_output(['git', 'show', '98a412c:upstream/recomp/host/dshow.m'], cwd=ROOT))
        flags = ['-DFNV_DSHOW_SOURCE="' + str(old) + '"', '-DFNV_DSHOW_REFERENCE']
    subprocess.run(['xcrun', 'clang', '-O1', '-fobjc-arc', '-I', str(HOST), '-I', str(ROOT/'upstream/recomp'), *flags,
                    str(ROOT/'tests/dshow_source_test.m'), str(HOST/'com.c'),
                    '-framework', 'Foundation', '-framework', 'AVFoundation', '-o', str(binary)], check=True)
    modes = ['source-render'] if args.reference else ['source-render', 'interfaces', 'playback', 'callback-trap', 'callback-stack', 'oversize', 'incomplete', 'read-failure']
    failures = []
    for mode in modes:
        result = subprocess.run([str(binary), mode], capture_output=True, text=True, timeout=20)
        print(result.stdout, end='')
        print(result.stderr, end='')
        if result.returncode:
            failures.append(mode)
    if args.reference:
        assert failures == ['source-render'], failures
        print('Historical success-only AddFilter/Render pipeline failure reproduced')
    else:
        assert not failures, failures

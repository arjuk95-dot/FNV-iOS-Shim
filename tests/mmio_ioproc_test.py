"""Verify custom WAV IOProc routing with authored archive-only RIFF data."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
host = root / 'upstream/recomp/host'
parser = argparse.ArgumentParser()
parser.add_argument('--reference', action='store_true')
args = parser.parse_args()
compiler = ['cc'] if shutil.which('cc') else ['xcrun', 'clang']
with tempfile.TemporaryDirectory(prefix='fnv-mmio-ioproc-') as temp:
    work = Path(temp)
    flags = []
    if args.reference:
        old = work / 'mmio.c'
        old.write_bytes(subprocess.check_output(
            ['git', 'show', '7006785:upstream/recomp/host/mmio.c'], cwd=root))
        flags = ['-DFNV_MMIO_SOURCE="' + str(old) + '"']
    binary = work / 'mmio-ioproc-test'
    subprocess.run([*compiler, '-O1', '-I', str(host), '-I', str(root/'upstream/recomp'),
                    *flags, str(root/'tests/mmio_ioproc_test.c'), '-o', str(binary)], check=True)
    modes = ['archive', 'loose']
    if not args.reference:
        modes += ['open-trap', 'open-stack', 'open-failure', 'read-trap', 'read-stack', 'read-failure', 'close-error']
    failures = []
    for mode in modes:
        result = subprocess.run([str(binary), mode], cwd=work, capture_output=True, text=True, timeout=15)
        print(result.stdout, end='')
        print(result.stderr, end='')
        if result.returncode:
            failures.append(mode)
    if args.reference:
        assert failures == ['archive'], failures
        print('Historical mmioOpenA omission of the supplied IOProc reproduced; loose control passes.')
    else:
        assert not failures, failures

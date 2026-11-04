"""Exercise original movie COM draws against real offscreen Metal, with authored pixels."""
import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
host = root / 'upstream/recomp/host'
parser = argparse.ArgumentParser()
parser.add_argument('--reference', action='store_true', help='reproduce the historical black draw')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='fnv-movie-draw-') as temp:
    work = Path(temp)
    flags = []
    if args.reference:
        old = work / 'd3d9_metal.m'
        old.write_bytes(subprocess.check_output(
            ['git', 'show', '91954eb:upstream/recomp/host/d3d9_metal.m'], cwd=root))
        flags += ['-DFNV_METAL_SOURCE="' + str(old) + '"', '-DFNV_MOVIE_REFERENCE']
    binary = work / 'movie-draw-test'
    common = ['xcrun', 'clang', '-O1', '-DFNV_PROBE', '-I', str(root/'ios'),
              '-I', str(host), '-I', str(root/'upstream/recomp')]
    objects = []
    sources = [root/'tests/movie_draw_test.m', root/'ios/FNVDisplay.c',
               *[host/(name+'.c') for name in ['d3d9', 'gheap', 'com', 'sm2msl']]]
    for index, source in enumerate(sources):
        obj = work / f'{index}.o'
        language = ['-fobjc-arc'] if source.suffix == '.m' else []
        subprocess.run([*common, *language, *flags, '-c', str(source), '-o', str(obj)], check=True)
        objects.append(str(obj))
    frameworks = ['Foundation', 'Metal', 'QuartzCore', 'CoreGraphics', 'AVFoundation',
                  'CoreVideo', 'CoreMedia', 'ImageIO', 'UniformTypeIdentifiers']
    subprocess.run(['xcrun', 'clang', *objects,
                    *[arg for name in frameworks for arg in ['-framework', name]], '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], cwd=work, timeout=45)
    if result.returncode == 77:
        print('SKIP: host has no Metal device; GPU pixel regression remains unverified.', flush=True)
    else:
        result.check_returncode()

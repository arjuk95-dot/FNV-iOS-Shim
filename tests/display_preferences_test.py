"""Check production display initialization against real COM and Win32 INI reads."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / 'upstream/recomp/host'
HISTORICAL = '98a412cc91827666d4e7eec66b82aa8f94688b22'


def run(*arguments):
    subprocess.run([str(a) for a in arguments], check=True)


def historical_initializer():
    """Extract the unchanged old initializer, rather than recreate its defect."""
    source = subprocess.check_output(
        ['git', 'show', HISTORICAL + ':ios/FNVApp.m'], cwd=ROOT
    ).decode('utf-8')
    start = source.index('    NSMutableArray<NSString*> *lines=')
    end = source.index('\n    [NSFileManager.defaultManager createDirectoryAtPath:', start)
    block = source[start:end]
    assert 'NSDictionary *settings=' in block and 'for(NSString *section in settings)' in block
    assert 'componentsJoinedByString' not in block and 'sD3DDevice' not in block
    return ('#import <Foundation/Foundation.h>\n#include "FNVDisplay.h"\n'
            'NSString *fnv_display_preferences(NSString *text) {\n'
            + block + '\n    return [lines componentsJoinedByString:@"\\n"];\n}\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='fnv-preferences-test-') as temporary:
        work = Path(temporary)
        preferences = ROOT / 'ios/FNVPreferences.m'
        if args.reference:
            preferences = work / 'historical_preferences.m'
            preferences.write_text(historical_initializer(), encoding='utf-8')
        includes = ['-I', ROOT / 'ios', '-I', HOST, '-I', ROOT / 'upstream/recomp']
        objective_objects = []
        for index, source in enumerate([ROOT / 'tests/display_preferences_test.m', preferences]):
            obj = work / f'foundation-{index}.o'
            run('xcrun', 'clang', '-O1', '-fobjc-arc', *includes, '-c', source, '-o', obj)
            objective_objects.append(obj)
        binary = work / 'display-preferences-test'
        run('xcrun', 'clang', '-O1', *includes,
            ROOT / 'tests/display_preferences_guest.c',
            ROOT / 'ios/FNVDisplay.c',
            *[HOST / (name + '.c') for name in ['d3d9_null', 'gheap', 'com', 'shims_files']],
            *objective_objects, '-framework', 'Foundation', '-o', binary)
        fixture = work / 'fixture'
        run(binary, fixture, 'reference' if args.reference else 'current')


if __name__ == '__main__':
    main()

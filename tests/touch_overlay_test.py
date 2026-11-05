"""Run the actual UIKit overlay in an isolated iOS simulator, with contact fixtures."""
import json
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build/touch-overlay-checks'
BUNDLE = 'dev.fnvshim.touch-overlay-tests'


def command(*args, timeout=90):
    return subprocess.check_output(list(args), text=True, timeout=timeout).strip()


def sim(*args, timeout=90):
    return command('xcrun', 'simctl', *args, timeout=timeout)


def main():
    assert platform.system() == 'Darwin', 'Native UIKit simulator validation requires Xcode on macOS'
    OUTPUT.mkdir(parents=True, exist_ok=True)
    runtime_candidates = [r for r in json.loads(sim('list', 'runtimes', '-j'))['runtimes']
                          if r.get('isAvailable') and '.iOS-' in r['identifier']]
    assert runtime_candidates, 'No installed iOS simulator runtime; do not report native UI checks as passed'
    runtime = max(runtime_candidates, key=lambda r: tuple(int(n) for n in r['version'].split('.')))
    device_type = 'com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro'
    identifier = sim('create', 'FNV isolated touch checks', device_type, runtime['identifier'])
    try:
        with tempfile.TemporaryDirectory(prefix='fnv-overlay-ui-') as folder:
            work = Path(folder)
            app = work / 'TouchOverlayTest.app'
            app.mkdir()
            sdk = command('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path')
            arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
            flags = ['xcrun', '--sdk', 'iphonesimulator', 'clang', '-isysroot', sdk,
                     '-target', f'{arch}-apple-ios18.0-simulator', '-O1',
                     '-I', str(ROOT / 'ios'), '-I', str(ROOT / 'upstream/recomp/host')]
            sources = [ROOT / 'tests/touch_overlay_test.m', ROOT / 'ios/FNVGameplayTouchView.m', ROOT / 'ios/FNVPad.c']
            objects = []
            for i, source in enumerate(sources):
                obj = work / f'{i}.o'
                subprocess.run([*flags, *(['-fobjc-arc'] if source.suffix == '.m' else []),
                                '-c', str(source), '-o', str(obj)], check=True)
                objects.append(str(obj))
            subprocess.run([*flags, *objects, *[a for f in ['UIKit', 'Foundation', 'CoreGraphics', 'QuartzCore', 'CoreMotion', 'GameController']
                                               for a in ['-framework', f]], '-o', str(app / 'TouchOverlayTest')], check=True)
            info = dict(CFBundleIdentifier=BUNDLE, CFBundleName='TouchOverlayTest',
                        CFBundleExecutable='TouchOverlayTest', CFBundlePackageType='APPL',
                        CFBundleVersion='1', CFBundleShortVersionString='1.0', MinimumOSVersion='18.0',
                        LSRequiresIPhoneOS=True, UIDeviceFamily=[1, 2], NSMotionUsageDescription='Isolated overlay regression fixture',
                        UISupportedInterfaceOrientations=['UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'])
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
            sim('boot', identifier)
            sim('bootstatus', identifier, '-b', timeout=150)
            sim('install', identifier, str(app))
            data = Path(sim('get_app_container', identifier, BUNDLE, 'data'))
            sim('launch', identifier, BUNDLE)
            report_path = data / 'Documents/OverlayTest/results.json'
            deadline = time.monotonic() + 60
            while not report_path.is_file() and time.monotonic() < deadline:
                time.sleep(1)
            assert report_path.is_file(), 'UIKit fixture did not produce a result'
            for source in report_path.parent.iterdir():
                if source.suffix in ['.png', '.json']:
                    shutil.copy2(source, OUTPUT / source.name)
            report = json.loads(report_path.read_text())
            for case in report['cases']:
                print(('PASS' if case['pass'] else 'FAIL') + ': ' + case['name'], flush=True)
            print(json.dumps(dict(native_uikit=True, simulator_runtime=runtime['identifier'],
                                  failures=report['failures'], cases=len(report['cases']),
                                  physical_gesture_recognition_verified=False)), flush=True)
            assert report['failures'] == 0, 'Native UIKit touch overlay regression failed'
    finally:
        subprocess.run(['xcrun', 'simctl', 'terminate', identifier, BUNDLE], capture_output=True, timeout=15)
        subprocess.run(['xcrun', 'simctl', 'shutdown', identifier], capture_output=True, timeout=30)
        subprocess.run(['xcrun', 'simctl', 'delete', identifier], capture_output=True, timeout=30)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Build an unsigned device IPA with the installed Xcode iPhoneOS SDK."""
import argparse
import concurrent.futures
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
R = ROOT / 'upstream/recomp'
H = R / 'host'
I = ROOT / 'ios'
def run(cmd):
    subprocess.run(cmd, check=True)
def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1<<20), b''):
            h.update(block)
    return h.hexdigest()

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('target', choices=['probe','game'])
    p.add_argument('--generated', type=Path, help='full-game emit.py output')
    p.add_argument('--exe', type=Path, help='exact executable used to generate these units')
    p.add_argument('--out', type=Path, default=Path('build'))
    p.add_argument('--jobs', type=int, default=min(os.cpu_count() or 2, 6))
    args = p.parse_args()
    probe = args.target == 'probe'
    if not probe and not (args.exe and args.exe.is_file() and args.generated and (args.generated/'table.c').is_file()
                          and (args.generated/'stubs.c').is_file() and any(args.generated.glob('tu_*.c'))):
        p.error('game requires --exe and --generated with full translated C sources')
    if not shutil.which('xcrun'): p.exit(1,'Apple build required: install Xcode and select it with xcode-select.\n')
    sdk = subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
    cc = subprocess.check_output(['xcrun','--sdk','iphoneos','--find','clang'],text=True).strip()
    name = 'FNVShimProbe' if probe else 'FNVGame'
    sources = [I/'FNVApp.m',I/'FNVGameplayTouchView.m',I/'FNVPad.c',H/'d3d9_metal.m']
    if probe:
        sources += [I/'FNVProbe.c', I/'ProbeRuntime.c']
        sources += [H/(s+'.c') for s in ['d3d9','dinput','com','gheap','input','sm2msl']]
    else:
        sources += [f for f in H.glob('*.c') if f.name != 'd3d9_null.c']
        sources += [H/'dshow.m',R/'rt_dispatch.c',args.generated/'table.c',args.generated/'stubs.c']
        sources += sorted(args.generated.glob('tu_*.c'))
    args.out.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.out) as temp:
        tmp=Path(temp)
        app=tmp/'Payload'/(name+'.app')
        app.mkdir(parents=True)
        base=[cc,'-target','arm64-apple-ios18.0','-isysroot',sdk]
        def compile_one(item):
            idx,source=item
            out=tmp/f'{idx}.o'
            flags=['-O1','-I',str(H),'-I',str(R),'-I',str(I)]
            if source.suffix=='.m': flags.append('-fobjc-arc')
            if probe: flags.append('-DFNV_PROBE')
            run(base + flags + ['-c',str(source),'-o',str(out)])
            return str(out)
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            objects=list(pool.map(compile_one, enumerate(sources)))
        frameworks=['Foundation','UIKit','Metal','QuartzCore','CoreGraphics','AVFoundation','CoreVideo','CoreMedia','ImageIO','UniformTypeIdentifiers']
        run(base+objects+[v for f in frameworks for v in ('-framework',f)]+['-o',str(app/name)])
        info=dict(CFBundleDevelopmentRegion='en',CFBundleExecutable=name,CFBundleName=name,CFBundleDisplayName=name,
                  CFBundleIdentifier='dev.fnvshim.'+args.target,CFBundlePackageType='APPL',CFBundleVersion='1',
                  CFBundleShortVersionString='0.1',CFBundleInfoDictionaryVersion='6.0',MinimumOSVersion='18.0',
                  CFBundleSupportedPlatforms=['iPhoneOS'],UIDeviceFamily=[1,2],LSRequiresIPhoneOS=True,
                  UIFileSharingEnabled=True,LSSupportsOpeningDocumentsInPlace=True,UILaunchScreen={},
                  UISupportedInterfaceOrientations=['UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'])
        if not probe: info['FNVExecutableSHA256']=digest(args.exe)
        (app/'Info.plist').write_bytes(plistlib.dumps(info))
        ipa=args.out/(name+'.ipa')
        with zipfile.ZipFile(tmp/ipa.name,'w',zipfile.ZIP_DEFLATED) as z:
            for f in app.iterdir(): z.write(f,f.relative_to(tmp))
        os.replace(tmp/ipa.name,ipa)
        print(ipa.resolve())
if __name__=='__main__': main()

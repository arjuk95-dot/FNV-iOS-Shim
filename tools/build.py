#!/usr/bin/env python3
"""Build an unsigned device IPA with the installed Xcode iPhoneOS SDK."""
import argparse
import concurrent.futures
import hashlib
import json
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
    p.add_argument('target', choices=['probe','game','host-check'])
    p.add_argument('--generated', type=Path, help='full-game emit.py output')
    p.add_argument('--exe', type=Path, help='exact executable used to generate these units')
    p.add_argument('--out', type=Path, default=Path('build'))
    p.add_argument('--jobs', type=int, default=min(os.cpu_count() or 2, 6))
    p.add_argument('--cache',type=Path,help='private verified object cache; compiler, SDK, flags, headers and content keyed')
    args = p.parse_args()
    probe = args.target == 'probe'
    host_check = args.target == 'host-check'
    if args.target == 'game' and not (args.exe and args.exe.is_file() and args.generated and (args.generated/'table.c').is_file()
                          and (args.generated/'stubs.c').is_file() and any(args.generated.glob('tu_*.c'))):
        p.error('game requires --exe and --generated with full translated C sources')
    if not shutil.which('xcrun'): p.exit(1,'Apple build required: install Xcode and select it with xcode-select.\n')
    sdk = subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
    cc = subprocess.check_output(['xcrun','--sdk','iphoneos','--find','clang'],text=True).strip()
    signature=hashlib.sha256(subprocess.check_output([cc,'--version'])+sdk.encode())
    for header in sorted({p for directory in [R,I] for p in directory.rglob('*.h')}):
        signature.update(str(header.relative_to(ROOT)).encode()+header.read_bytes())
    config=signature.digest();old_manifest={}
    if args.cache:
        args.cache.mkdir(parents=True,exist_ok=True)
        if (args.cache/'manifest.json').exists():old_manifest=json.loads((args.cache/'manifest.json').read_text())
    name = 'FNVShimProbe' if probe else 'FNVGame'
    sources = [I/'FNVApp.m',I/'FNVGameplayTouchView.m',I/'FNVPad.c',H/'d3d9_metal.m']
    if probe:
        sources += [I/'FNVProbe.c', I/'ProbeRuntime.c']
        sources += [H/(s+'.c') for s in ['d3d9','dinput','com','gheap','input','sm2msl']]
    else:
        sources += [f for f in H.glob('*.c') if f.name != 'd3d9_null.c']
        sources += [H/'dshow.m',R/'rt_dispatch.c']
        if not host_check:
            sources += [args.generated/'table.c',args.generated/'stubs.c']
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
            elif not host_check: flags.append('-DRT_CALLTRACE')
            key=hashlib.sha256(config+json.dumps(base+flags).encode()+source.name.encode()+source.read_bytes()).hexdigest()
            stored=args.cache/(key+'.o') if args.cache else None
            if stored and stored.exists() and digest(stored)==old_manifest.get(stored.name):return str(stored),True
            run(base + flags + ['-c',str(source),'-o',str(out)])
            if stored:os.replace(out,stored);out=stored
            return str(out),False
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            compiled=list(pool.map(compile_one, enumerate(sources)))
        objects=[path for path,_ in compiled]
        print(f'iOS objects: {sum(reused for _,reused in compiled)} reused, {sum(not reused for _,reused in compiled)} compiled',flush=True)
        if args.cache:
            (args.cache/'manifest.json').write_text(json.dumps({Path(path).name:digest(Path(path)) for path in objects},indent=2))
        if host_check:
            print(f'PASS: compiled {len(objects)} public game-host sources for arm64 iPhoneOS; no game inputs or IPA')
            return
        frameworks=['Foundation','UIKit','Metal','QuartzCore','CoreGraphics','AVFoundation','CoreVideo','CoreMedia','ImageIO','UniformTypeIdentifiers']
        run(base+objects+[v for f in frameworks for v in ('-framework',f)]+['-o',str(app/name)])
        info=dict(CFBundleDevelopmentRegion='en',CFBundleExecutable=name,CFBundleName=name,CFBundleDisplayName=name,
                  CFBundleIdentifier='dev.fnvshim.'+args.target,CFBundlePackageType='APPL',CFBundleVersion=os.environ.get('GITHUB_RUN_NUMBER','1'),
                  CFBundleShortVersionString='0.1',CFBundleInfoDictionaryVersion='6.0',MinimumOSVersion='18.0',
                  CFBundleSupportedPlatforms=['iPhoneOS'],UIDeviceFamily=[1,2],LSRequiresIPhoneOS=True,
                  UIFileSharingEnabled=True,LSSupportsOpeningDocumentsInPlace=True,UILaunchScreen={},
                  UISupportedInterfaceOrientations=['UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'])
        if not probe: info['FNVExecutableSHA256']=digest(args.exe)
        try:
            info['FNVBuildSourceCommit']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,stderr=subprocess.DEVNULL).strip()
        except (OSError, subprocess.CalledProcessError):
            pass
        (app/'Info.plist').write_bytes(plistlib.dumps(info))
        ipa=args.out/(name+'.ipa')
        with zipfile.ZipFile(tmp/ipa.name,'w',zipfile.ZIP_DEFLATED) as z:
            for f in app.iterdir(): z.write(f,f.relative_to(tmp))
        os.replace(tmp/ipa.name,ipa)
        print(ipa.resolve())
if __name__=='__main__': main()

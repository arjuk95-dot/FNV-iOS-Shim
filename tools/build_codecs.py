"""Build pinned BSD Ogg/Vorbis libraries for a native Apple target; no game inputs."""
import argparse,hashlib,json,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PINS={'ogg':('v1.3.5','e1774cd77f471443541596e09078e78fdc342e4f'),
      'vorbis':('v1.3.7','0657aee69dec8508a0011f47f3b69d7538e9d262')}
def run(args,**kw):subprocess.run([str(x) for x in args],check=True,**kw)
def main():
    p=argparse.ArgumentParser();p.add_argument('platform',choices=['ios','macos']);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);prefix=out/'prefix'
    sdk='iphoneos' if a.platform=='ios' else 'macosx'
    sdkpath=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
    compiler=subprocess.check_output(['xcrun','--sdk',sdk,'--find','clang'],text=True).strip()
    for name,(tag,pin) in PINS.items():
        source=out/(name+'-source')
        if not source.exists():run(['git','clone','--depth','1','--branch',tag,'https://github.com/xiph/'+name+'.git',source])
        actual=subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip()
        if actual!=pin:raise ValueError('Public codec source identity mismatch: '+name)
        build=out/(name+'-build')
        common=['cmake','-S',source,'-B',build,'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_C_COMPILER='+compiler,
          '-DCMAKE_OSX_ARCHITECTURES=arm64','-DCMAKE_OSX_SYSROOT='+sdkpath,
          '-DCMAKE_OSX_DEPLOYMENT_TARGET='+('18.0' if a.platform=='ios' else '15.0'),
          '-DCMAKE_SYSTEM_NAME='+('iOS' if a.platform=='ios' else 'Darwin'),
          '-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY','-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
          '-DCMAKE_INSTALL_PREFIX='+str(prefix),'-DCMAKE_PREFIX_PATH='+str(prefix),
          '-DBUILD_SHARED_LIBS=OFF','-DBUILD_TESTING=OFF','-DINSTALL_DOCS=OFF']
        if name=='vorbis':common+=['-DOGG_LIBRARY='+str(prefix/'lib/libogg.a'),'-DOGG_INCLUDE_DIR='+str(prefix/'include')]
        run(common);run(['cmake','--build',build,'--parallel','3']);run(['cmake','--install',build])
        licenses=prefix/'licenses';licenses.mkdir(exist_ok=True);shutil.copyfile(source/'COPYING',licenses/(name+'-COPYING'))
    for name in ['ogg','vorbis','vorbisfile','vorbisenc']:
        assert (prefix/'lib'/('lib'+name+'.a')).is_file(),name
    manifest={'platform':a.platform,'architecture':'arm64','pins':PINS,'sdk':sdkpath,'files':{}}
    for f in prefix.rglob('*'):
        if f.is_file():manifest['files'][str(f.relative_to(prefix))]=hashlib.sha256(f.read_bytes()).hexdigest()
    (prefix/'codec-manifest.json').write_text(json.dumps(manifest,indent=2))
    print('PASS: pinned native codec libraries built for '+a.platform,flush=True)
if __name__=='__main__':main()

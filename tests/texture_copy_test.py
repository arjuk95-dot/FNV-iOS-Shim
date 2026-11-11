from native_test_toolchain import COMPILER, PLATFORM_FLAGS, LIBRARIES
import argparse,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];host=root/'upstream/recomp/host'
p=argparse.ArgumentParser();p.add_argument('--reference',action='store_true');args=p.parse_args()
with tempfile.TemporaryDirectory() as temp:
    work=Path(temp);binary=work/'copy-test';flags=[]
    if args.reference:
        old=work/'d3d9.c';old.write_bytes(subprocess.check_output(['git','show','5e803ea:upstream/recomp/host/d3d9.c'],cwd=root));flags=['-DFNV_D3D_SOURCE="'+str(old)+'"']
    subprocess.run([*COMPILER,*PLATFORM_FLAGS,'-O1','-I',str(root/'ios'),'-I',str(host),'-I',str(root/'upstream/recomp'),*flags,
        str(root/'tests/texture_copy_test.c'),str(root/'ios/FNVDisplay.c'),
        *[str(host/(n+'.c')) for n in ['d3d9_null','gheap','com']],*LIBRARIES,'-o',str(binary)],check=True)
    failed=[]
    for mode in (['surface','texture'] if args.reference else ['surface','texture','cube-chain','rectangle']):
        for fmt in [int.from_bytes(n.encode(),'little') for n in ['DXT1','DXT3','DXT5','ATI1','ATI2']]+[21]:
            result=subprocess.run([str(binary),mode,str(fmt)],timeout=20)
            if result.returncode:failed.append((mode,fmt))
    if args.reference:assert len(failed)==10,failed;print('Historical compressed-copy overwrites reproduced:',len(failed))
    elif failed:raise SystemExit('Copy regressions: '+str(failed))

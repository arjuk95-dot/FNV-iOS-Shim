import argparse,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];host=root/'upstream/recomp/host'
p=argparse.ArgumentParser();p.add_argument('--reference',action='store_true');args=p.parse_args()
with tempfile.TemporaryDirectory() as temp:
    work=Path(temp);binary=work/'lifetime-test';flags=[]
    if args.reference:
        old=work/'d3d9.c';old.write_bytes(subprocess.check_output(['git','show','5e803ea:upstream/recomp/host/d3d9.c'],cwd=root))
        flags=['-DFNV_D3D_SOURCE="'+str(old)+'"']
    subprocess.run(['xcrun','clang','-O1','-I',str(root/'ios'),'-I',str(host),'-I',str(root/'upstream/recomp'),*flags,
        str(root/'tests/texture_lifetime_test.c'),str(root/'ios/FNVDisplay.c'),
        *[str(host/(n+'.c')) for n in ['d3d9_null','gheap','com']],'-o',str(binary)],check=True)
    failed=[]
    for mode in ['bound-get-rebind','texture-stages','stream-index','render-target-depth']+([] if args.reference else ['shader-declaration']):
        result=subprocess.run([str(binary),mode],timeout=20)
        if result.returncode:failed.append(mode)
    if args.reference:assert len(failed)==4,failed;print('Historical lifetime failures reproduced:',failed)
    elif failed:raise SystemExit('Lifetime regressions: '+','.join(failed))

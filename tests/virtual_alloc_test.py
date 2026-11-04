import argparse,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--reference',action='store_true');args=p.parse_args()
with tempfile.TemporaryDirectory() as temp:
    temp=Path(temp);binary=temp/'virtual-test';flags=[]
    if args.reference:
        for name,macro in [('gheap','FNV_GHEAP_SOURCE'),('shims_kernel32','FNV_KERNEL_SOURCE')]:
            file=temp/(name+'.c');file.write_bytes(subprocess.check_output(['git','show','5576821:upstream/recomp/host/'+name+'.c'],cwd=root));flags+=['-D'+macro+'="'+str(file)+'"']
    subprocess.run(['xcrun','clang','-O1','-ffunction-sections','-fdata-sections','-I',str(root/'ios'),'-I',str(root/'upstream/recomp/host'),'-I',str(root/'upstream/recomp'),
        *flags,str(root/'tests/virtual_alloc_test.c'),'-Wl,-dead_strip','-o',str(binary)],check=True)
    failures=[]
    for mode in ['occupied','future-heap','future-pages','unreserved-commit','partial-commit','rounding','valid-commit','overflow','zero','spanning-future','spanning-occupied','adjacent']:
        result=subprocess.run([str(binary),mode],timeout=15)
        if result.returncode:failures.append(mode)
    if args.reference:
        assert {'occupied','future-heap','future-pages','unreserved-commit','partial-commit','rounding','overflow','zero'}<=set(failures),failures
        print('Historical defects reproduced:',','.join(failures))
    elif failures:raise SystemExit('Failed: '+','.join(failures))

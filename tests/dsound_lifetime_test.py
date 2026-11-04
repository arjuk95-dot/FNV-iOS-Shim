import argparse,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];host=root/'upstream/recomp/host'
p=argparse.ArgumentParser();p.add_argument('--reference',action='store_true');args=p.parse_args()
with tempfile.TemporaryDirectory() as folder:
    work=Path(folder);binary=work/'sound-lifetime';flags=[]
    if args.reference:
        old=work/'dsound.c';old.write_bytes(subprocess.check_output(['git','show','ab36dd5:upstream/recomp/host/dsound.c'],cwd=root));flags=['-DFNV_DSOUND_SOURCE="'+str(old)+'"']
    subprocess.run(['xcrun','clang','-O1','-I',str(root/'ios'),'-I',str(host),'-I',str(root/'upstream/recomp'),*flags,
        str(root/'tests/dsound_lifetime_test.c'),str(root/'ios/FNVAudioMixer.c'),str(host/'com.c'),'-o',str(binary)],check=True)
    failures=[]
    for mode in ['sdk-destructor','independent-counts','listener','canonical-interface','unknown-iid','duplicate-spatial']:
        result=subprocess.run([str(binary),mode],capture_output=True,text=True,timeout=20)
        print(result.stdout,end='');print(result.stderr,end='')
        if result.returncode:failures.append(mode)
        if args.reference and mode=='sdk-destructor':assert 'reason=freed-pointer' in result.stderr and 'alias=1' in result.stdout
    if args.reference:assert len(failures)==6,failures;print('Historical SDK IID/interface lifetime failures reproduced:',len(failures))
    else:assert not failures,failures

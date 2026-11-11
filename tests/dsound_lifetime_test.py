from native_test_toolchain import COMPILER, PLATFORM_FLAGS, LIBRARIES
import argparse,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];host=root/'upstream/recomp/host'
p=argparse.ArgumentParser();p.add_argument('--reference',action='store_true');args=p.parse_args()
with tempfile.TemporaryDirectory() as folder:
    work=Path(folder);binary=work/'sound-lifetime';flags=[]
    if args.reference:
        old=work/'dsound.c';old.write_bytes(subprocess.check_output(['git','show','ab36dd5:upstream/recomp/host/dsound.c'],cwd=root));flags=['-DFNV_DSOUND_SOURCE="'+str(old)+'"']
    subprocess.run([*COMPILER,*PLATFORM_FLAGS,'-O1','-I',str(root/'ios'),'-I',str(host),'-I',str(root/'upstream/recomp'),*flags,
        str(root/'tests/dsound_lifetime_test.c'),str(root/'ios/FNVAudioMixer.c'),str(host/'com.c'),*LIBRARIES,'-o',str(binary)],check=True)
    failures=[]
    for mode in ['sdk-destructor','sdk-min-distance-abi','independent-counts','listener','canonical-interface','unknown-iid','duplicate-spatial']:
        result=subprocess.run([str(binary),mode],capture_output=True,text=True,timeout=20)
        print(result.stdout,end='');print(result.stderr,end='')
        assert result.returncode != 125, 'Core-dump test setup failed: '+mode
        if result.returncode:failures.append(mode)
        if args.reference and mode=='sdk-destructor':assert 'reason=freed-pointer' in result.stderr and 'alias=1' in result.stdout
    if args.reference:
        assert len(failures)==7,failures;print('Historical SDK IID/interface lifetime failures reproduced:',len(failures))
        old_heap=work/'gheap.c';old_heap.write_bytes(subprocess.check_output(['git','show','499fa3d:upstream/recomp/host/gheap.c'],cwd=root))
        alias=work/'sound-graphics-alias'
        subprocess.run([*COMPILER,*PLATFORM_FLAGS,'-O1','-I',str(root/'ios'),'-I',str(host),'-I',str(root/'upstream/recomp'),*flags,'-DFNV_OLD_HEAP','-DFNV_GHEAP_SOURCE="'+str(old_heap)+'"',
            str(root/'tests/dsound_lifetime_test.c'),str(root/'ios/FNVAudioMixer.c'),str(host/'com.c'),*LIBRARIES,'-o',str(alias)],check=True)
        result=subprocess.run([str(alias),'sdk-destructor'],capture_output=True,text=True,timeout=20)
        print(result.stdout,end='');assert result.returncode==0 and 'AUDIO-TO-GRAPHICS ALIAS:' in result.stdout,(result.returncode,result.stderr)
    else:assert not failures,failures

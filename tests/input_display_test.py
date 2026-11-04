from pathlib import Path
import subprocess,tempfile,sys
root=Path(__file__).resolve().parents[1];host=root/'upstream/recomp/host'
with tempfile.TemporaryDirectory() as temp:
    binary=Path(temp)/'input-test'
    compiler=['xcrun','clang'] if sys.platform=='darwin' else ['cc']
    platform_flags=['-include',str(root/'tests/linux_time.h')] if sys.platform.startswith('linux') else []
    libraries=['-lm','-pthread'] if sys.platform.startswith('linux') else []
    subprocess.run([*compiler,'-O1','-DFNV_GAME_INPUT_CONTEXT',*platform_flags,'-I',str(root/'ios'),'-I',str(host),'-I',str(root/'upstream/recomp'),
        str(root/'tests/input_display_test.c'),str(root/'ios/FNVPad.c'),str(root/'ios/FNVDisplay.c'),
        *[str(host/(n+'.c')) for n in ['dinput','input','com']],*libraries,'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=10)

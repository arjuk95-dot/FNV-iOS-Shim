from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1];host=root/'upstream/recomp/host'
with tempfile.TemporaryDirectory() as temp:
    binary=Path(temp)/'input-test'
    subprocess.run(['xcrun','clang','-O1','-I',str(root/'ios'),'-I',str(host),'-I',str(root/'upstream/recomp'),
        str(root/'tests/input_display_test.c'),str(root/'ios/FNVPad.c'),str(root/'ios/FNVDisplay.c'),
        *[str(host/(n+'.c')) for n in ['dinput','input','com']],'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=10)

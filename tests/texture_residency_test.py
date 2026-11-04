import subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];host=root/'upstream/recomp/host'
with tempfile.TemporaryDirectory() as temp:
    binary=Path(temp)/'texture-test'
    subprocess.run(['xcrun','clang','-O1','-I',str(root/'ios'),'-I',str(host),'-I',str(root/'upstream/recomp'),
        str(root/'tests/texture_residency_test.c'),str(root/'ios/FNVDisplay.c'),
        *[str(host/(n+'.c')) for n in ['d3dx9','d3d9_null','gheap','com']],'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=60)

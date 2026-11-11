from native_test_toolchain import COMPILER, PLATFORM_FLAGS, LIBRARIES
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temp:
    binary=Path(temp)/'bink-test'
    subprocess.run([*COMPILER,*PLATFORM_FLAGS,'-O1','-I',str(root/'ios'),'-I',str(root/'upstream/recomp/host'),'-I',str(root/'upstream/recomp'),
        str(root/'tests/bink_shims_test.c'),str(root/'upstream/recomp/host/media.c'),*LIBRARIES,'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=10)

from native_test_toolchain import COMPILER, PLATFORM_FLAGS, LIBRARIES
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temp:
    binary=Path(temp)/'audio-test'
    subprocess.run([*COMPILER,*PLATFORM_FLAGS,'-O1','-I',str(ROOT/'ios'),'-I',str(ROOT/'upstream/recomp/host'),'-I',str(ROOT/'upstream/recomp'),
        str(ROOT/'tests/audio_shims_test.c'),str(ROOT/'ios/FNVAudioMixer.c'),str(ROOT/'upstream/recomp/host/dsound.c'),
        str(ROOT/'upstream/recomp/host/com.c'),*LIBRARIES,'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=10)

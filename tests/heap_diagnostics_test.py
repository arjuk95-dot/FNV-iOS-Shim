from native_test_toolchain import COMPILER, PLATFORM_FLAGS, LIBRARIES
import subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];host=root/'upstream/recomp/host'
with tempfile.TemporaryDirectory() as temp:
    binary=Path(temp)/'heap-diagnostic-test'
    subprocess.run([*COMPILER,*PLATFORM_FLAGS,'-O1','-I',str(root/'ios'),'-I',str(host),'-I',str(root/'upstream/recomp'),str(root/'tests/heap_diagnostics_test.c'),*LIBRARIES,'-o',str(binary)],check=True)
    for mode,reason in [('tail','tail-overwrite'),('header','size-header-overwrite'),('class','class-header-overwrite'),('double-free','freed-pointer'),('unowned','unowned-pointer'),('bad-free-list','free-list-pointer'),('live-free-list','free-list-pointer')]:
        run=subprocess.run([str(binary),mode],capture_output=True,text=True,timeout=10)
        assert run.returncode and '[heap-corruption]' in run.stderr and 'reason='+reason in run.stderr,(mode,run.returncode,run.stderr)
        print('PASS: first fault stopped:',mode,reason)
    subprocess.run([str(binary),'valid'],check=True,timeout=20)

"""Same native guest-style register/memory result with tracing enabled and omitted."""
from native_test_toolchain import COMPILER, PLATFORM_FLAGS, LIBRARIES
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='fnv-calltrace-') as temp:
    outputs=[]
    for enabled in [True,False]:
        binary=Path(temp)/('trace-on' if enabled else 'trace-off')
        flags=['-DRT_CALLTRACE'] if enabled else []
        subprocess.run([*COMPILER,*PLATFORM_FLAGS,'-O1',*flags,'-I',str(root/'upstream/recomp'),
                        str(root/'tests/calltrace_equivalence_test.c'),*LIBRARIES,'-o',str(binary)],check=True)
        outputs.append(subprocess.check_output([str(binary)]))
    assert outputs[0]==outputs[1] and len(outputs[0].strip())==16
    print('PASS: 30000 authored guest-style entries preserve identical CPU registers, flags and guest memory with call tracing on/off')

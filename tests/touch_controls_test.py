"""Run production touch policy and source arbitration on the native host."""
from pathlib import Path
import os
import runpy
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
if os.name=='nt':
    runpy.run_path(str(root/'tests/touch_controls_windows.py'),run_name='__main__')
else:
    with tempfile.TemporaryDirectory(prefix='fnv-touch-test-') as folder:
        binary=Path(folder)/'touch-test'
        compiler=['xcrun','clang'] if sys.platform=='darwin' else ['cc']
        subprocess.run([*compiler,'-O1','-I',str(root/'ios'),'-I',str(root/'upstream/recomp/host'),
                        str(root/'tests/touch_controls_test.c'),str(root/'ios/FNVPad.c'),
                        '-lm','-pthread','-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True,timeout=15)

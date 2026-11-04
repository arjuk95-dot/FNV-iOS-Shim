"""Exercise the production preference loader with an isolated native defaults suite."""
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='fnv-touch-settings-') as folder:
    binary=Path(folder)/'touch-settings-test'
    subprocess.run(['xcrun','clang','-fobjc-arc','-O1','-I',str(root/'ios'),
                    str(root/'tests/touch_settings_test.m'),'-framework','Foundation','-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=20)

from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temp:
    binary=Path(temp)/'video-test'
    subprocess.run(['xcrun','clang','-O1','-fobjc-arc','-I',str(root/'ios'),str(root/'tests/native_video_test.m'),str(root/'ios/FNVNativeVideo.m'),
        *[v for f in ['Foundation','AVFoundation','CoreVideo','CoreMedia'] for v in ['-framework',f]],'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)

"""Run actual production touch policy and pad ownership on existing MSVC."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
vswhere=Path('C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe')
devcmd=Path(subprocess.check_output([str(vswhere),'-all','-products','*','-find','Common7/Tools/VsDevCmd.bat'],text=True).strip().splitlines()[0])
with tempfile.TemporaryDirectory(prefix='fnv-touch-test-',dir=root.parent/'private-work') as directory:
    work=Path(directory)
    (work/'pthread.h').write_text('#include <windows.h>\ntypedef SRWLOCK pthread_mutex_t;\n#define PTHREAD_MUTEX_INITIALIZER SRWLOCK_INIT\nstatic int pthread_mutex_lock(pthread_mutex_t *p){AcquireSRWLockExclusive(p);return 0;}\nstatic int pthread_mutex_unlock(pthread_mutex_t *p){ReleaseSRWLockExclusive(p);return 0;}\n')
    (work/'compile.cmd').write_text(f'@echo off\ncall "{devcmd}" -arch=x64 >nul\nif errorlevel 1 exit /b 1\ncl /nologo /std:c11 /O1 /W3 /I"{work}" /I"{root/"ios"}" /I"{root/"upstream/recomp/host"}" /Fe:touch-test.exe "{root/"tests/touch_controls_test.c"}" "{root/"ios/FNVPad.c"}"\n',encoding='utf-8')
    subprocess.run(['cmd.exe','/d','/c','compile.cmd'],cwd=work,check=True)
    result=subprocess.run([str(work/'touch-test.exe')],capture_output=True,text=True,timeout=15)
    print(result.stdout,end='');print(result.stderr,end='')
    receipt=dict(platform='Windows x64 / existing MSVC',production_source_sha256=hashlib.sha256((root/'ios/FNVPad.c').read_bytes()).hexdigest(),policy_sha256=hashlib.sha256((root/'ios/FNVTouchPolicy.h').read_bytes()).hexdigest(),runtime_function_bodies_unchanged=True,platform_adapter='SRW locks provide pthread mutex API; input_key is an unused legacy stub',exit_code=result.returncode,output=result.stdout+result.stderr,limitations='UIKit, CoreMotion, native guest menu sampler and device behavior require Apple build/phone validation.')
    (root.parent/'receipts/touch-controls-windows.json').write_text(json.dumps(receipt,indent=2))
    if result.returncode:raise SystemExit(result.returncode)

"""Compile the production allocator with MSVC using Win32 header adapters; no runtime function edits."""
import hashlib,json,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
vswhere=Path('C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe')
devcmd=Path(subprocess.check_output([str(vswhere),'-all','-products','*','-find','Common7/Tools/VsDevCmd.bat'],text=True).strip().splitlines()[0])
source=(root/'upstream/recomp/host/gheap.c').read_bytes()
assert source.count(b'#include "host.h"')==1 and source.count(b'#include <pthread.h>')==1
adapted=source.replace(b'#include "host.h"',b'/* host memory accessors supplied by the test harness */').replace(b'#include <pthread.h>',b'/* mutex adapter supplied by the test harness */')
results=[]
with tempfile.TemporaryDirectory(prefix='windows-heap-test-',dir=root.parent/'private-work') as folder:
    work=Path(folder).resolve();assert work.is_relative_to((root.parent/'private-work').resolve())
    (work/'gheap-under-test.c').write_bytes(adapted);(work/'heap-test.c').write_bytes((root/'tests/heap_ownership_windows.c').read_bytes())
    (work/'compile.cmd').write_text(f'@echo off\ncall "{devcmd}" -arch=x64 >nul\nif errorlevel 1 exit /b 1\ncl /nologo /std:c11 /O1 /W3 /Fe:heap-test.exe heap-test.c\n',encoding='utf-8')
    subprocess.run(['cmd.exe','/d','/c','compile.cmd'],cwd=work,check=True)
    for mode in ['empty-spanning','occupied-spanning','future-heap','future-pages','adjacent','recycling']:
        run=subprocess.run([str(work/'heap-test.exe'),mode],capture_output=True,text=True,timeout=30)
        print(run.stdout,end='');print(run.stderr,end='');results.append(dict(mode=mode,exit_code=run.returncode,output=run.stdout+run.stderr))
    receipt=dict(platform='Windows x64 / MSVC',source_sha256=hashlib.sha256(source).hexdigest(),runtime_function_bodies_unchanged=True,
                 adapters='Windows demand-committed guest address space, SRW mutex, G32/P32; original platform includes replaced only',results=results)
    (root.parent/'receipts/heap-ownership-windows.json').write_text(json.dumps(receipt,indent=2))
    if any(r['exit_code'] for r in results):raise SystemExit('Native allocator regression failed')

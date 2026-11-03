"""Compare real pthread/wait behavior before and after the synchronization repair."""
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
BASELINE='c533f6e7365088af0fd943c911413fbeccbf5c05'
with tempfile.TemporaryDirectory(prefix='fnv-sync-test-') as temp:
    temp=Path(temp)
    baseline=temp/'baseline.c'
    baseline.write_bytes(subprocess.check_output(['git','show',BASELINE+':upstream/recomp/host/shims_sync.c'],cwd=ROOT))
    outputs={}
    for name,module in [('historical',baseline),('repaired',ROOT/'upstream/recomp/host/shims_sync.c')]:
        binary=temp/name
        subprocess.run(['xcrun','clang','-O1','-DRT_CALLTRACE',*(['-DFNV_TEST_DIAGNOSTICS'] if name=='repaired' else []),'-I',str(ROOT/'upstream/recomp/host'),'-I',str(ROOT/'upstream/recomp'),
                        str(ROOT/'tests/sync_shims_test.c'),str(module),'-o',str(binary)],check=True)
        result=subprocess.run([str(binary)],capture_output=True,text=True,timeout=10)
        print(name+'\n'+result.stdout+result.stderr,flush=True)
        outputs[name]=result
    assert outputs['historical'].returncode==1,'Historical module must demonstrate the regressions'
    for failure in ['wait-all preserves auto-reset signal on timeout','wait-all preserves semaphore count on timeout',
                    'wait-all completes after second event arrives','ExitThread signals and records explicit exit code',
                    'finite wait spans monotonic second boundary']:
        assert 'FAIL: '+failure in outputs['historical'].stdout,failure
    assert outputs['repaired'].returncode==0,'Repaired module must pass every behavior check'
    assert '[sync-snapshot] tid=1 state=present object=0 caller=0x401123' in outputs['repaired'].stderr
    assert 'recent_entries=0x401002,0x401001,0x401000' in outputs['repaired'].stderr

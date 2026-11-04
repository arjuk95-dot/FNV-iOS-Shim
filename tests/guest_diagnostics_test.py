from pathlib import Path
import subprocess
import tempfile
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from state_probes import normalize,instrument
spec=normalize('[{"entry":"0x401000","offsets":[0,8,16]}]')
original=b'#include "rt.h"\nvoid g(CPU *c){RT_ENTER(0x401000u);LOAD_ENTRY;}\nvoid other(CPU *c){RT_ENTER(0x402000u);LOAD_ENTRY;}'
changed,matched=instrument(original,spec)
assert matched=={0x401000} and changed.count(b'rt_diag_watch(c,')==1
assert b'RT_ENTER(0x402000u);LOAD_ENTRY;' in changed
entry_only,matched=instrument(original,normalize('[{"entry":"0x402000","offsets":[]}]'))
assert matched=={0x402000} and b'rt_diag_watch(c,0x402000u,(const uint32_t *)0,0);' in entry_only
with tempfile.TemporaryDirectory() as temp:
    out=Path(temp)/'diagnostic-test'
    subprocess.run(['xcrun','clang','-O1','-I',str(ROOT/'upstream/recomp/host'),'-I',str(ROOT/'upstream/recomp'),
                    str(ROOT/'tests/guest_diagnostics_test.c'),str(ROOT/'upstream/recomp/host/guest_diagnostics.c'),'-o',str(out)],check=True)
    result=subprocess.run([str(out)],capture_output=True,text=True,check=True)
    assert len(result.stderr.splitlines())==13,'Samples must remain bounded'
    assert 'caller=0x401123 object=0x8000 fields=0:0x123,0x8:0x456,0x10:0x789 frames=0x401234,0x402345,' in result.stderr
    assert 'entry=0x402000 sample=1 caller=0x401123 object=0xfffffff8 fields= frames=' in result.stderr
    assert 'args=0x1234,0x5678,0,0' in result.stderr
    print(result.stdout,flush=True)
    print('PASS: selected fields, entry-only probes, stack arguments and bounded frame chain; 12 samples for 1024 repeated entries',flush=True)

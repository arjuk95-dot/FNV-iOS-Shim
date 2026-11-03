"""The pre-phone gate must reject traps, abnormal exits and stalled startup."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
cases = [
    ('clean', 'pass', 0, False),
    ('trap_with_zero_exit', "print('[host] TRAP (thread 1): no function at address at 0x1234')", 1, False),
    ('error_three', 'raise SystemExit(3)', 1, False),
    ('stalled', 'import time; time.sleep(10)', 1, True),
]
with tempfile.TemporaryDirectory() as directory:
    for name, program, expected, timeout in cases:
        folder = Path(directory)/name
        folder.mkdir()
        guest = folder/'synthetic.py'
        guest.write_text(program)
        out = folder/'result'
        result = subprocess.run([sys.executable, str(ROOT/'tools/run_startup.py'),
                                 sys.executable, str(guest), '--out', str(out), '--timeout', '1'],
                                capture_output=True, text=True, timeout=10)
        assert result.returncode == expected, (name, result.stdout, result.stderr)
        receipt = json.loads((out/'strict-startup-result.json').read_text())
        assert receipt['timed_out'] == timeout, name
        assert receipt['title_or_gameplay_verified'] is False, name
        if name == 'trap_with_zero_exit':
            assert receipt['translation_traps'], name
        if name == 'error_three':
            assert receipt['returncode'] == 3, name
print('PASS: startup gate rejects traps even with exit 0, exit 3 and timeouts; never claims gameplay')

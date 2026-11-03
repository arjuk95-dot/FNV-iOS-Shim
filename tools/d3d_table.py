"""Generate the 32-bit stdcall metadata used by the New Vegas host from MinGW d3d9.h."""
import re
import sys
from pathlib import Path

def generate(header, host):
    header = re.sub(r'/\*.*?\*/', '', header, flags=re.S)
    interfaces = sorted(set(re.findall(r'\bVT\((IDirect\w+),', host)))
    out = ['/* Direct3D9 COM slot names and argument counts, excluding this. */', '#pragma once']
    for iface in interfaces:
        body = re.search(r'DECLARE_INTERFACE_IID_\(' + iface + r',[^\n]+\n\s*\{(.*?)\};', header, re.S)[1]
        pattern = r'STDMETHOD(?:_\(\s*[^,]+,\s*(\w+)\s*\)|\((\w+)\))\s*\(THIS(_\s*(.*?))?\)\s*PURE;'
        methods = []
        for m in re.finditer(pattern, body, re.S):
            args = m[4].strip() if m[4] else ''
            if re.search(r'\b(double|UINT64|INT64|LONGLONG)\b(?!\s*\*)', args, re.I):
                raise ValueError('Check 32-bit stack width: ' + args)
            methods.append((m[1] or m[2], len(args.split(',')) if args else 0))
        assert len(methods) == body.count('PURE;') and [p[0] for p in methods[:3]] == ['QueryInterface','AddRef','Release'], iface
        assert len(set(n for n, _ in methods)) == len(methods)
        if iface == 'IDirect3DDevice9':
            assert len(methods) == 119 and methods[17] == ('Present',4) and methods[43] == ('Clear',6)
        out.extend([f'enum {{ {iface}_COUNT = {len(methods)} }};',
                    f'static const char *const {iface}_names[] = {{' + ', '.join(f'"{n}"' for n,_ in methods) + '};',
                    f'static const unsigned char {iface}_nargs[] = {{' + ', '.join(str(k) for _,k in methods) + '};'])
    assert len(interfaces) == 13
    return '\n'.join(out) + '\n'

if __name__ == '__main__':
    out = Path(sys.argv[3])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(generate(Path(sys.argv[1]).read_text(), Path(sys.argv[2]).read_text()))

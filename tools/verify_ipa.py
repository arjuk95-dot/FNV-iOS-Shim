#!/usr/bin/env python3
"""Verify an unsigned arm64 iPhoneOS IPA without running its code."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import stat
import struct
import zipfile


def verify(path, target):
    name = 'FNVShimProbe' if target == 'probe' else 'FNVGame'
    prefix = f'Payload/{name}.app/'
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f'ZIP integrity failure: {bad}')
        entries = archive.infolist()
        if len({entry.filename for entry in entries}) != len(entries):
            raise ValueError('Duplicate ZIP member')
        for entry in entries:
            parts = Path(entry.filename).parts
            if '..' in parts or entry.filename.startswith(('/', '\\')):
                raise ValueError('Unsafe ZIP member path')
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        assert info['CFBundleExecutable'] == name
        assert info['CFBundleIdentifier'] == 'dev.fnvshim.' + target
        assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
        assert info['LSRequiresIPhoneOS'] is True
        assert info['UIFileSharingEnabled'] is True
        exe_info = archive.getinfo(prefix + name)
        mode = exe_info.external_attr >> 16
        assert stat.S_ISREG(mode) and mode & 0o111, 'Executable ZIP mode missing'
        binary = archive.read(exe_info)
    magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<8I', binary)
    assert magic == 0xFEEDFACF, 'Expected thin little-endian Mach-O 64'
    assert cpu == 0x0100000C and filetype == 2, 'Expected arm64 executable'
    assert 32 + sizeofcmds <= len(binary)
    cursor, frameworks, platforms = 32, [], []
    for _ in range(ncmds):
        command, size = struct.unpack_from('<II', binary, cursor)
        assert size >= 8 and cursor + size <= 32 + sizeofcmds
        if command == 0x32:
            platforms.append(struct.unpack_from('<I', binary, cursor + 8)[0])
        if command in (0xC, 0x80000018, 0x8000001F):
            start = cursor + struct.unpack_from('<I', binary, cursor + 8)[0]
            assert cursor <= start < cursor + size
            end = binary.index(b'\0', start, cursor + size)
            frameworks.append(binary[start:end].decode())
        cursor += size
    assert cursor == 32 + sizeofcmds
    assert platforms == [2], f'Expected iOS device platform, got {platforms}'
    assert any('/UIKit.framework/' in item for item in frameworks), 'UIKit missing'
    assert not any('/AppKit.framework/' in item for item in frameworks), 'AppKit linked'
    if target == 'game':
        assert len(info['FNVExecutableSHA256']) == 64
    return dict(target=target, ipa=str(path.resolve()), sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                bytes=path.stat().st_size, bundle_id=info['CFBundleIdentifier'], architecture='arm64',
                platform='iPhoneOS', executable_mode=oct(mode & 0o777), zip_members=len(entries),
                dylibs=frameworks, unsigned=True, executable_sha256=info.get('FNVExecutableSHA256'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--target', choices=['probe', 'game'], required=True)
    parser.add_argument('--receipt', type=Path)
    args = parser.parse_args()
    result = verify(args.ipa, args.target)
    encoded = json.dumps(result, indent=2)
    if args.receipt:
        args.receipt.write_text(encoded + '\n')
    print(encoded)


if __name__ == '__main__':
    main()

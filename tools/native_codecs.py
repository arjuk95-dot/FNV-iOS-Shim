"""Validate content-addressed pinned public codec inputs before compiling or linking."""
import hashlib,json
from pathlib import Path
from build_codecs import PINS
def validate(prefix,platform):
    prefix=Path(prefix).resolve()
    manifest=json.loads((prefix/'codec-manifest.json').read_text())
    if manifest['platform']!=platform or manifest['architecture']!='arm64' or manifest['pins']!={k:list(v) for k,v in PINS.items()}:
        raise ValueError('Wrong codec architecture, platform or source pins')
    for relative,expected in manifest['files'].items():
        f=(prefix/relative).resolve()
        if not f.is_relative_to(prefix) or hashlib.sha256(f.read_bytes()).hexdigest()!=expected:
            raise ValueError('Codec file identity mismatch: '+relative)
    for required in ['include/vorbis/vorbisfile.h','lib/libvorbisfile.a','lib/libvorbis.a','lib/libogg.a','licenses/ogg-COPYING','licenses/vorbis-COPYING']:
        if required not in manifest['files']:raise ValueError('Incomplete codec manifest: '+required)
    return prefix

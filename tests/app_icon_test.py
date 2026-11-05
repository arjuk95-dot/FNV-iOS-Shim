"""Compile real iPhone/iPad icon renditions and verify their bundle metadata."""
from pathlib import Path
import struct
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from app_icon import compile_icon

with tempfile.TemporaryDirectory(prefix='fnv-icon-test-') as directory:
    work=Path(directory)
    app=work/'FNVGame.app'
    app.mkdir()
    info=compile_icon(work,app)
    for key in ['CFBundleIcons','CFBundleIcons~ipad']:
        icon=info[key]['CFBundlePrimaryIcon']
        assert icon['CFBundleIconName']=='AppIcon' and icon['CFBundleIconFiles']
        for stem in icon['CFBundleIconFiles']:
            assert any(app.glob(stem+'*.png')),'Icon plist points to a missing rendition'
    sizes={struct.unpack_from('>II',p.read_bytes(),16) for p in app.glob('*.png')}
    assert {(120,120),(180,180),(152,152),(167,167)}<=sizes
    assert struct.unpack_from('>II',(app/info['CFBundleIconFile']).read_bytes(),16)==(1024,1024)
    assert (app/'Assets.car').stat().st_size>1024
    print('PASS: real iPhone/iPad icon renditions, primary-icon metadata and compiled asset catalog')

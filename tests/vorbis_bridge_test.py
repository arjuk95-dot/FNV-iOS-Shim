import argparse,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('prefix',type=Path);a=p.parse_args();prefix=a.prefix.resolve()
with tempfile.TemporaryDirectory() as temp:
    binary=Path(temp)/'vorbis-test'
    subprocess.run(['xcrun','clang','-O1','-DFNV_HAVE_VORBIS','-I',str(prefix/'include'),'-I',str(ROOT/'upstream/recomp/host'),
        '-I',str(ROOT/'upstream/recomp'),str(ROOT/'tests/vorbis_bridge_test.c'),str(ROOT/'upstream/recomp/host/media_vorbis.c'),
        *[str(prefix/'lib'/('lib'+name+'.a')) for name in ['vorbisfile','vorbisenc','vorbis','ogg']],'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=20)

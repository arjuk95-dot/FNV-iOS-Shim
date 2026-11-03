"""Use a real case-sensitive APFS fixture; no game inputs are involved."""
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
def run(*args):subprocess.run([str(a) for a in args],check=True)
with tempfile.TemporaryDirectory(prefix='fnv-file-test-') as temp:
    base=Path(temp);image=base/'case.sparseimage';mount=base/'volume';mount.mkdir()
    run('hdiutil','create','-size','128m','-type','SPARSE','-fs','Case-sensitive APFS','-volname','FNVCaseFixture',image)
    attached=False
    try:
        run('hdiutil','attach',image,'-mountpoint',mount,'-nobrowse');attached=True
        fixture=mount/'fixture';(fixture/'Data').mkdir(parents=True)
        (fixture/'Data/Fallout - Misc.bsa').write_bytes(b'marker')
        ini=fixture/'UserDocuments/My Games/FalloutNV/FALLOUT.INI';ini.parent.mkdir(parents=True)
        ini.write_text('[Archive]\nSArchiveList=example.bsa\n')
        assert not (fixture/'data').exists(),'Test fixture must actually distinguish path case'
        binary=base/'file-shims-test'
        run('xcrun','clang','-O1','-I',ROOT/'upstream/recomp/host','-I',ROOT/'upstream/recomp',
            ROOT/'tests/file_shims_case_test.c',ROOT/'upstream/recomp/host/shims_files.c','-o',binary)
        run(binary,fixture)
    finally:
        if attached:run('hdiutil','detach',mount)

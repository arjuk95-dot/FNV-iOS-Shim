"""A bounded real case-sensitive APFS scratch volume for host compatibility tests."""
from contextlib import contextmanager
from pathlib import Path
import subprocess
import tempfile

@contextmanager
def case_sensitive_root():
    with tempfile.TemporaryDirectory(prefix='fnv-case-fixture-') as temp:
        base=Path(temp);image=base/'case.sparseimage';mount=base/'volume';mount.mkdir()
        def run(*args):subprocess.run([str(a) for a in args],check=True)
        run('hdiutil','create','-size','128m','-type','SPARSE','-fs','Case-sensitive APFS','-volname','FNVCaseFixture',image)
        attached=False
        try:
            run('hdiutil','attach',image,'-mountpoint',mount,'-nobrowse');attached=True
            fixture=mount/'fixture';fixture.mkdir();yield fixture
        finally:
            if attached:run('hdiutil','detach',mount)

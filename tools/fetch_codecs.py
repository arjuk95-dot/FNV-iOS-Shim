"""Fetch the pinned public codec prefix, including its preserved artifact backup."""
import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tempfile
import zipfile
from native_codecs import validate

PRESERVED_TAG='fnv-public-codecs-41685697032'
PRESERVED_SHA={
    'ios':'963a2e8bf41a7f6602854da2990ce178220875514cca80d145209e090ace706f',
    'macos':'e7e444cc6c2d02b1ee50b82be447738cec5f494adcfdafdb5e99cca3aa71be07',
}

def fetch(run,platform,destination,repository=None):
    if not run.isdigit():raise ValueError('Numeric codec run ID required')
    destination=Path(destination).resolve()
    if destination.exists():
        validate(destination,platform)
        return destination
    destination.parent.mkdir(parents=True,exist_ok=True)
    repo=repository or os.environ.get('GITHUB_REPOSITORY','arjuk95-dot/FNV-iOS-Shim')
    with tempfile.TemporaryDirectory(prefix='fnv-codecs-',dir=destination.parent) as directory:
        work=Path(directory).resolve()
        assert work.is_relative_to(destination.parent)
        artifact=work/'artifact'
        downloaded=subprocess.run(['gh','run','download',run,'--repo',repo,'--name',f'FNV-public-codecs-{platform}','--dir',str(artifact)])
        if downloaded.returncode==0:
            validate(artifact,platform)
            prefix=artifact
        else:
            if run!='41685697032':raise RuntimeError('Requested codec artifact is unavailable')
            cache=work/'preserved';cache.mkdir()
            name=f'FNV-public-codecs-{platform}.zip'
            subprocess.run(['gh','release','download',PRESERVED_TAG,'--repo',repo,'--pattern',name,'--dir',str(cache)],check=True)
            archive=cache/name
            if hashlib.sha256(archive.read_bytes()).hexdigest()!=PRESERVED_SHA[platform]:
                raise ValueError('Preserved codec archive SHA-256 mismatch')
            prefix=work/'prefix'
            with zipfile.ZipFile(archive) as z:
                for member in z.infolist():
                    relative=PurePosixPath(member.filename)
                    if relative.is_absolute() or '..' in relative.parts or '\\' in member.filename:
                        raise ValueError('Invalid preserved codec member')
                z.extractall(prefix)
            validate(prefix,platform)
            print(f'PASS: recovered exact pinned {platform} codecs from the preserved cache',flush=True)
        shutil.copytree(prefix,destination)
    return validate(destination,platform)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform',choices=['ios','macos'])
    parser.add_argument('--run',default='41685697032')
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--repo',help='repository containing the pinned public codecs when using a separate private build repository')
    args=parser.parse_args()
    print(fetch(args.run,args.platform,args.out,args.repo),flush=True)

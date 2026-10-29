"""Install only the standalone app; never touches ICA or printer drivers."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

NAME = 'HP M1217 Native Scan.app'
IDENTIFIER = 'local.hp-m1217.native-scan'


def validate(app):
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != IDENTIFIER:
        raise ValueError('Unexpected application identifier')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    for name in ['NativeScan', 'marvell_capture', 'decode_capture']:
        arch = subprocess.check_output(['lipo', '-archs', str(app/'Contents/MacOS'/name)], text=True).strip()
        if arch != 'arm64':
            raise ValueError('Unexpected architecture: '+arch)


def install(source, destination):
    validate(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation protects an existing installation, including symlinks.
    destination.mkdir()
    try:
        shutil.copytree(source, destination, dirs_exist_ok=True, symlinks=True)
        validate(destination)
    except BaseException:
        shutil.rmtree(destination)
        raise
    return destination


def rollback(destination, trash):
    if destination.is_symlink():
        raise ValueError('Refusing a symlink')
    validate(destination)
    trash.mkdir(parents=True, exist_ok=True)
    target = trash/(NAME.removesuffix('.app')+'-'+str(uuid.uuid4())+'.app')
    destination.rename(target)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install', 'rollback'])
    args = parser.parse_args()
    destination = Path.home()/'Applications'/NAME
    if args.action == 'install':
        local = Path(__file__).resolve().parent
        source = local/NAME
        if not source.exists():
            source = local/'build'/NAME
        print(install(source, destination))
    else:
        print(rollback(destination, Path.home()/'.Trash'))

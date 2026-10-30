"""Build only. Does not install, create queues or contact printers."""
from pathlib import Path
import subprocess,shutil,hashlib
root=Path(__file__).resolve().parent
build=root/'build';build.mkdir(exist_ok=True)
binary=build/'hp-m1217-urf'
subprocess.run(['clang','-arch','arm64','-O2','-Wall','-Wextra','-Werror','urf_filter.c','-o',str(binary)],cwd=root,check=True)
subprocess.run(['codesign','--force','--sign','-',str(binary)],check=True)
subprocess.run(['codesign','--verify','--strict',str(binary)],check=True)
assert subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()=='arm64'
payload=build/'root'
if payload.exists():shutil.rmtree(payload)
base=payload/'Library/Printers/HPNative1217';(base/'Filters').mkdir(parents=True)
shutil.copy2(binary,base/'Filters/hp-m1217-urf')
for source in ['HP-M1217-Native.ppd','README.md']:
 shutil.copy2(root/source,base/source)
shutil.copy2(root.parent/'LICENSE',base/'LICENSE')
scripts=build/'scripts';scripts.mkdir(exist_ok=True)
pre=scripts/'preinstall';pre.write_text('''#!/bin/sh
set -eu
if [ -e "$3/Library/Printers/HPNative1217" ] || [ -L "$3/Library/Printers/HPNative1217" ]; then
 echo "Existing HP native print driver preserved; refusing overwrite." >&2
 exit 1
fi
''');pre.chmod(0o755)
pkg=build/'HP-M1217-Native-Print-0.1.0-arm64.pkg'
subprocess.run(['pkgbuild','--root',str(payload),'--scripts',str(scripts),'--identifier','local.hp-m1217.native-print','--version','0.1.0','--install-location','/',str(pkg)],check=True)
(build/'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in [pkg,binary]))
print(pkg)

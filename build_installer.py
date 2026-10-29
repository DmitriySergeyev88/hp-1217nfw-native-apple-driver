"""Create standalone app installer only. Does not install or alter ICA/printing."""
from pathlib import Path
import plistlib,shutil,subprocess,hashlib
root=Path(__file__).resolve().parent
build=root/'scanner/build/installer';payload=build/'root/Applications';payload.mkdir(parents=True,exist_ok=True)
app=root/'scanner/build/HP M1217 Native Scan.app'
shutil.copytree(app,payload/app.name,dirs_exist_ok=True)
scripts=build/'scripts';scripts.mkdir(exist_ok=True)
pre=scripts/'preinstall'
pre.write_text('''#!/bin/sh
set -eu
if [ -e "$3/Applications/HP M1217 Native Scan.app" ] || [ -L "$3/Applications/HP M1217 Native Scan.app" ]; then
 echo "Existing app preserved. Move it to a backup folder before installing this version." >&2
 exit 1
fi
''');pre.chmod(0o755)
components=build/'components.plist'
subprocess.run(['pkgbuild','--analyze','--root',str(build/'root'),str(components)],check=True)
items=plistlib.loads(components.read_bytes())
for item in items:item['BundleIsRelocatable']=False
components.write_bytes(plistlib.dumps(items))
dist=root/'dist';dist.mkdir(exist_ok=True);pkg=dist/'HP-M1217-Native-Scan-0.2.0-arm64.pkg'
subprocess.run(['pkgbuild','--root',str(build/'root'),'--component-plist',str(components),'--scripts',str(scripts),'--identifier','local.hp-m1217.native-scan.package','--version','0.2.0','--install-location','/',str(pkg)],check=True)
(dist/'SHA256SUMS').write_text(hashlib.sha256(pkg.read_bytes()).hexdigest()+'  '+pkg.name+'\n')
print(pkg)

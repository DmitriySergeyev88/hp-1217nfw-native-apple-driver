"""Build only isolated ICA artifacts. No installation, publication or scanning."""
import os
os.environ.setdefault("MACOSX_DEPLOYMENT_TARGET", "11.0")
from pathlib import Path
import hashlib
import plistlib
import shutil
import subprocess

root=Path(__file__).resolve().parent.parent
build=root/'build/ica'
build.mkdir(parents=True,exist_ok=True)
(root.parent/'dist').mkdir(exist_ok=True)
def run(*args): subprocess.run(args,check=True,cwd=root)
run('clang','-arch','arm64','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations',
    '-framework','Foundation','-framework','ICADevices','-framework','ImageCaptureCore',
    '-framework','ImageIO','-framework','CoreGraphics','ica/NativeICA.m','-o',str(build/'NativeICA'))
run('clang','-arch','arm64','-fobjc-arc','-Wall','-Wextra','-Werror','-framework','AppKit',
    'ica/Discovery.m','-o',str(build/'ICADiscovery'))
run('clang','-arch','arm64','-fobjc-arc','-Wall','-Wextra','-Werror','-framework','Foundation','-framework','ImageCaptureCore',
    'ica/ICAClient.m','-o',str(build/'ICAClient'))
run(str(build/'NativeICA'),'--test');run(str(build/'ICADiscovery'),'--test')

def bundle(name,executable,identifier,extra):
    app=build/(name+'.app')
    if app.exists(): shutil.rmtree(app)
    mac=app/'Contents/MacOS';mac.mkdir(parents=True,exist_ok=True)
    shutil.copy2(build/executable,mac/executable)
    info={'CFBundleExecutable':executable,'CFBundleIdentifier':identifier,'CFBundleName':name,
          'CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.2.1','CFBundleVersion':'3',
          'LSMinimumSystemVersion':'11.0','LSBackgroundOnly':True,
          'NSLocalNetworkUsageDescription':'Обнаружение и сканирование HP M1217 через Захват изображений.'}
    info.update(extra);
    if info.get('LSUIElement'): info.pop('LSBackgroundOnly',None)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info));return app

module=bundle('HP M1217 Native ICA','NativeICA','local.hp-m1217.native-ica',{'NSPrincipalClass':'NSApplication','NSMainNibFile':'MainMenu'})
shutil.copy2(root/'build/marvell_capture',module/'Contents/MacOS/marvell_capture')
res=module/'Contents/Resources';res.mkdir(exist_ok=True)
(res/'DeviceMatchingInfo.plist').write_bytes(plistlib.dumps({'Version':'1.0','BonjourNetwork':{'_scanner._tcp.':[
    {'device type':'scanner','device events':['scan'],'scan port':'8290',
     'ICABonjourTXTRecordKey':{'mfg':'NativeM1217','mdl':'M1217nfw'}}]}}))
(res/'DeviceInfo.plist').write_bytes(plistlib.dumps({'device info version':'3.0','devices':{
    'HP M1217 Native ICA':{'functionalUnitDescriptions':[{'type':0},{'type':3}],
    'iconFile':'/System/Library/Image Capture/Support/Icons/GenericScanner.icns'}}}))
shutil.copy2(root/'ica/APPLE_LICENSE.txt',res/'APPLE_LICENSE.txt')
publisher=bundle('HP M1217 ICA Discovery','ICADiscovery','local.hp-m1217.ica-discovery',{'LSUIElement':True})
run('codesign','--force','--sign','-',str(module/'Contents/MacOS/marvell_capture'))
for app in [module,publisher]:
    resources=app/'Contents/Resources';resources.mkdir(exist_ok=True)
    shutil.copy2(root.parent/'LICENSE',resources/'LICENSE')
    run('codesign','--force','--sign','-',str(app));run('codesign','--verify','--deep','--strict',str(app))
    for binary in (app/'Contents/MacOS').iterdir():
        assert subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()=='arm64'

if os.environ.get('HP_COMPONENTS_ONLY') == '1':
    print('PASS native ICA bundles; no legacy packages changed')
    raise SystemExit(0)

pkgroot=build/'pkg-root'
if pkgroot.exists(): shutil.rmtree(pkgroot)
staging=build/'pkg-root/Library/Image Capture/Devices';staging.mkdir(parents=True,exist_ok=True)
shutil.copytree(module,staging/module.name,dirs_exist_ok=True)
applications=pkgroot/'Applications';applications.mkdir()
shutil.copytree(publisher,applications/publisher.name)
components=build/'components.plist'
run('pkgbuild','--analyze','--root',str(build/'pkg-root'),str(components))
entries=plistlib.loads(components.read_bytes())
for entry in entries:
    entry['BundleIsRelocatable']=False
components.write_bytes(plistlib.dumps(entries))
scripts=build/'pkg-scripts';scripts.mkdir(exist_ok=True)
preinstall=scripts/'preinstall'
preinstall.write_text('#!/bin/sh\nset -eu\nfor relative in \'Library/Image Capture/Devices/HP M1217 Native ICA.app\' \'Applications/HP M1217 ICA Discovery.app\'; do\n if [ -e "$3/$relative" ] || [ -L "$3/$relative" ]; then\n  echo "Existing component preserved; installation refused: $relative" >&2\n  exit 1\n fi\ndone\n')
preinstall.chmod(0o755)
run('pkgbuild','--root',str(build/'pkg-root'),'--identifier','local.hp-m1217.native-ica.package',
    '--component-plist',str(components),'--scripts',str(scripts),
    '--version','0.2.1','--install-location','/',str(root.parent/'dist/HP-M1217-Native-ICA-0.2.1-arm64.pkg'))
print('PASS isolated ICA package; standalone app and system drivers untouched')

dist=root.parent/"dist"
(dist/"SHA256SUMS").write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in sorted(dist.glob("*.pkg"))))

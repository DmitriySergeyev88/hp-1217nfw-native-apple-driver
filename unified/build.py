"""Build one distributable package. Never install, configure queues or access an MFP."""
import os,plistlib,shutil,subprocess,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];HERE=ROOT/'unified';BUILD=HERE/'build';VERSION='0.3.0'
os.environ['MACOSX_DEPLOYMENT_TARGET']='11.0'
def run(*args):subprocess.run(args,cwd=ROOT,check=True)
run('sh','scanner/build.sh');run('env','HP_COMPONENTS_ONLY=1','python3','scanner/ica/build_ica.py');run('python3','printing/pclm/build.py')
BUILD.mkdir(exist_ok=True)
run('clang','-arch','arm64','-fobjc-arc','-Wall','-Wextra','-Werror','-framework','AppKit','-framework','ImageCaptureCore',str(HERE/'Setup.m'),'-o',str(BUILD/'Setup'))
run(str(BUILD/'Setup'),'--test')
payload=BUILD/'root'
if payload.exists():shutil.rmtree(payload)
apps=payload/'Applications';apps.mkdir(parents=True)
for src in [ROOT/'scanner/build/HP M1217 Native Scan.app',ROOT/'scanner/build/ica/HP M1217 ICA Discovery.app']:
 shutil.copytree(src,apps/src.name)
ica=payload/'Library/Image Capture/Devices';ica.mkdir(parents=True)
shutil.copytree(ROOT/'scanner/build/ica/HP M1217 Native ICA.app',ica/'HP M1217 Native ICA.app')
setup=apps/'HP M1217 Setup.app';mac=setup/'Contents/MacOS';mac.mkdir(parents=True)
shutil.copy2(BUILD/'Setup',mac/'Setup')
(setup/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'Setup','CFBundleIdentifier':'local.hp-m1217.setup','CFBundleName':'HP M1217 Setup','CFBundlePackageType':'APPL','CFBundleShortVersionString':VERSION,'CFBundleVersion':'1','LSMinimumSystemVersion':'11.0','NSLocalNetworkUsageDescription':'Связь очереди печати с нативным сканером / Link the print queue with the native scanner.'}))
run('codesign','--force','--sign','-',str(setup))
base=payload/'Library/Printers/HPNative1217PCLm';(base/'Filters').mkdir(parents=True)
shutil.copy2(ROOT/'printing/pclm/build/hp-m1217-pclm',base/'Filters/hp-m1217-pclm')
for name in ['HP-M1217-PCLm.ppd','README.md']:shutil.copy2(ROOT/'printing/pclm'/name,base/name)
for name in ['configure-queue.sh','uninstall.sh']:shutil.copy2(HERE/name,base/name)
shutil.copy2(ROOT/'LICENSE',base/'LICENSE')
for file in payload.rglob('*'):
 if file.is_file() and file.read_bytes()[:4]==b'\xcf\xfa\xed\xfe':
  assert subprocess.check_output(['lipo','-archs',str(file)],text=True).strip()=='arm64'
for app in list(apps.glob('*.app'))+list(ica.glob('*.app')):run('codesign','--verify','--deep','--strict',str(app))
scripts=BUILD/'scripts';scripts.mkdir(exist_ok=True)
paths=['Applications/HP M1217 Native Scan.app','Applications/HP M1217 ICA Discovery.app','Applications/HP M1217 Setup.app','Library/Image Capture/Devices/HP M1217 Native ICA.app','Library/Printers/HPNative1217PCLm']
pre='#!/bin/sh\nset -eu\n[ "$(uname -m)" = arm64 ] || exit 1\n'
for p in paths:pre+=f'if [ -e "$3/{p}" ] || [ -L "$3/{p}" ]; then echo "Existing component preserved: {p}. Back it up before installing." >&2; exit 1; fi\n'
(scripts/'preinstall').write_text(pre);(scripts/'preinstall').chmod(0o755)
components=BUILD/'components.plist';run('pkgbuild','--analyze','--root',str(payload),str(components))
items=plistlib.loads(components.read_bytes())
for item in items:item['BundleIsRelocatable']=False
components.write_bytes(plistlib.dumps(items))
component=BUILD/'component.pkg';run('pkgbuild','--root',str(payload),'--component-plist',str(components),'--scripts',str(scripts),'--identifier','local.hp-m1217.unified','--version',VERSION,str(component))
xml=BUILD/'Distribution.xml';xml.write_text(f'''<?xml version="1.0"?><installer-gui-script minSpecVersion="2"><title>HP M1217 Native Print &amp; Scan {VERSION}</title><options customize="never" require-scripts="false" hostArchitectures="arm64"/><allowed-os-versions><os-version min="11.0"/></allowed-os-versions><domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/><choices-outline><line choice="default"/></choices-outline><choice id="default" visible="false"><pkg-ref id="local.hp-m1217.unified"/></choice><pkg-ref id="local.hp-m1217.unified" version="{VERSION}">component.pkg</pkg-ref></installer-gui-script>''')
dist=ROOT/'dist';dist.mkdir(exist_ok=True);pkg=dist/f'HP-M1217-Native-Print-Scan-{VERSION}-arm64.pkg'
run('productbuild','--distribution',str(xml),'--package-path',str(BUILD),str(pkg))
(dist/'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in sorted(dist.glob('*.pkg'))))
print(pkg)

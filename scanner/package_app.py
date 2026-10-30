"""Build an isolated app bundle; never installs or contacts the scanner."""
from pathlib import Path
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parent
app = root / 'build/HP M1217 Native Scan.app'
macos = app / 'Contents/MacOS'
macos.mkdir(parents=True, exist_ok=True)
for name in ['NativeScan', 'marvell_capture', 'decode_capture']:
    shutil.copy2(root / 'build' / name, macos / name)
info = {
    'CFBundleExecutable': 'NativeScan',
    'CFBundleIdentifier': 'local.hp-m1217.native-scan',
    'CFBundleName': 'HP M1217 Native Scan',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.2.0',
    'CFBundleVersion': '2',
    'LSMinimumSystemVersion': '11.0',
    'NSHighResolutionCapable': True,
    'NSLocalNetworkUsageDescription': 'Сканирование на HP M1217 в вашей локальной сети.',
}
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
resources=app/'Contents/Resources'
resources.mkdir(exist_ok=True)
shutil.copy2(root.parent/'LICENSE', resources/'LICENSE')
for name in ['marvell_capture', 'decode_capture']:
    subprocess.run(['codesign', '--force', '--sign', '-', str(macos/name)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
for name in ['NativeScan', 'marvell_capture', 'decode_capture']:
    arch = subprocess.check_output(['lipo', '-archs', str(macos/name)], text=True).strip()
    assert arch == 'arm64', (name, arch)
subprocess.run([str(macos/'NativeScan'), '--test'], check=True)
print('PASS app bundle, ad-hoc signature, arm64-only executables; not installed')

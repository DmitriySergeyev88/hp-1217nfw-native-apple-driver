"""Inspect installer and run preflight only against a temporary fake target."""
from pathlib import Path
import hashlib,plistlib,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
PKG=ROOT/'dist/HP-M1217-Native-Print-Scan-0.3.0-arm64.pkg'
class UnifiedTests(unittest.TestCase):
 def test_installer_payload_and_preflight(self):
  with tempfile.TemporaryDirectory() as temp:
   temp=Path(temp);expanded=temp/'expanded'
   subprocess.run(['pkgutil','--expand-full',str(PKG),str(expanded)],check=True,capture_output=True)
   setups=list(expanded.rglob('HP M1217 Setup.app'));self.assertEqual(len(setups),1)
   applications=set(p.name for p in expanded.rglob('*.app'))
   self.assertEqual(applications,{'HP M1217 Setup.app','HP M1217 Native Scan.app','HP M1217 ICA Discovery.app','HP M1217 Native ICA.app'})
   for app in expanded.rglob('*.app'):
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes());self.assertEqual(info['LSMinimumSystemVersion'],'11.0')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
   binaries=[]
   for f in expanded.rglob('*'):
    if f.is_file() and f.read_bytes()[:4]==b'\xcf\xfa\xed\xfe':
     binaries.append(f);self.assertEqual(subprocess.check_output(['lipo','-archs',str(f)],text=True).strip(),'arm64')
     build=subprocess.check_output(['vtool','-show-build',str(f)],text=True);self.assertIn('minos 11.0',build)
   self.assertGreaterEqual(len(binaries),7)
   self.assertEqual(len(list(expanded.rglob('hp-m1217-pclm'))),1)
   ppd=next(expanded.rglob('HP-M1217-PCLm.ppd')).read_text();self.assertIn('application/pdf application/PCLm',ppd);self.assertNotIn('APScannerUUID',ppd)
   self.assertIn('APICADriver: True',ppd)
   pre=next(expanded.rglob('preinstall'));fake=temp/'fake';fake.mkdir()
   ok=subprocess.run(['sh',str(pre),'unused','/',str(fake)],capture_output=True);self.assertEqual(ok.returncode,0,ok.stderr)
   conflict=fake/'Applications/HP M1217 Native Scan.app';conflict.mkdir(parents=True)
   rejected=subprocess.run(['sh',str(pre),'unused','/',str(fake)],capture_output=True);self.assertNotEqual(rejected.returncode,0);self.assertTrue(conflict.exists())
 def test_checksums(self):
  for line in (ROOT/'dist/SHA256SUMS').read_text().splitlines():
   sha,name=line.split('  ',1);self.assertEqual(hashlib.sha256((ROOT/'dist'/name).read_bytes()).hexdigest(),sha)
if __name__=='__main__':unittest.main()

"""Offline checks; no installation, preferences changes or scanner access."""
from pathlib import Path
import subprocess,tempfile,unittest,plistlib
ROOT=Path(__file__).resolve().parent
class ICAInstallerTest(unittest.TestCase):
    def test_payload_and_guards(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);expanded=root/'expanded'
            subprocess.run(['pkgutil','--expand-full',str(ROOT/'dist/HP-M1217-Native-ICA-0.2.1-arm64.pkg'),str(expanded)],check=True)
            payloads=list(expanded.rglob('Payload'));self.assertEqual(len(payloads),1)
            payload=payloads[0]
            paths=['Library/Image Capture/Devices/HP M1217 Native ICA.app','Applications/HP M1217 ICA Discovery.app']
            self.assertEqual({str(p.relative_to(payload)) for p in payload.rglob('*.app')},set(paths))
            for p in payload.rglob('*'):
                if p.is_file(): self.assertTrue(any(str(p.relative_to(payload)).startswith(x+'/') for x in paths))
            for relative,exe in zip(paths,['NativeICA','ICADiscovery']):
                app=payload/relative
                subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
                for binary in (app/'Contents/MacOS').iterdir():
                    self.assertEqual(subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip(),'arm64')
                subprocess.run([str(app/'Contents/MacOS'/exe),'--test'],check=True)
            info=plistlib.loads((payload/paths[1]/'Contents/Info.plist').read_bytes())
            self.assertTrue(info['LSUIElement']);self.assertNotIn('LSBackgroundOnly',info)
            scripts=list(expanded.rglob('preinstall'));self.assertEqual(len(scripts),1)
            target=root/'target';target.mkdir()
            args=['/bin/sh',str(scripts[0]),'package','/',str(target)]
            self.assertEqual(subprocess.run(args,capture_output=True).returncode,0)
            for relative in paths:
                existing=target/relative;existing.parent.mkdir(parents=True,exist_ok=True);existing.write_text('preserve')
                self.assertNotEqual(subprocess.run(args,capture_output=True).returncode,0)
                self.assertEqual(existing.read_text(),'preserve')
                existing.unlink();existing.symlink_to(root/'missing')
                self.assertNotEqual(subprocess.run(args,capture_output=True).returncode,0)
                existing.unlink()
if __name__=='__main__':unittest.main()

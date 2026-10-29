"""Validate installer payload and overwrite guard without system installation."""
from pathlib import Path
import subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parent
class InstallerTest(unittest.TestCase):
    def test_payload_and_guard(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);expanded=root/'expanded'
            subprocess.run(['pkgutil','--expand-full',str(ROOT/'dist/HP-M1217-Native-Scan-0.2.0-arm64.pkg'),str(expanded)],check=True)
            payloads=list(expanded.rglob('Payload'));self.assertEqual(len(payloads),1)
            payload=payloads[0];app=payload/'Applications/HP M1217 Native Scan.app'
            self.assertEqual({p.name for p in payload.iterdir()},{'Applications'})
            self.assertEqual({p.name for p in (payload/'Applications').iterdir()},{app.name})
            subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
            subprocess.run([str(app/'Contents/MacOS/NativeScan'),'--test'],check=True)
            scripts=list(expanded.rglob('preinstall'));self.assertEqual(len(scripts),1)
            target=root/'target';target.mkdir()
            args=['/bin/sh',str(scripts[0]),'package','/',str(target)]
            self.assertEqual(subprocess.run(args,capture_output=True).returncode,0)
            existing=target/'Applications'/app.name;existing.parent.mkdir();existing.write_text('preserve')
            self.assertNotEqual(subprocess.run(args,capture_output=True).returncode,0)
            self.assertEqual(existing.read_text(),'preserve')
            existing.unlink();existing.symlink_to(root/'missing')
            self.assertNotEqual(subprocess.run(args,capture_output=True).returncode,0)
if __name__=='__main__':unittest.main()

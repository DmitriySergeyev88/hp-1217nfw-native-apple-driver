"""Build the standalone arm64 filter; no installation or printer access."""
import os
os.environ.setdefault("MACOSX_DEPLOYMENT_TARGET", "11.0")
from pathlib import Path
import subprocess,hashlib
root=Path(__file__).resolve().parent
out=root/'build';out.mkdir(exist_ok=True)
binary=out/'hp-m1217-pclm'
subprocess.run(['clang','-arch','arm64','-O2','-fobjc-arc','-Wall','-Wextra','-Werror',
 '-framework','Foundation','-framework','CoreGraphics','-framework','ImageIO',str(root/'pclm_filter.m'),'-o',str(binary)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(binary)],check=True)
subprocess.run(['codesign','--verify','--strict',str(binary)],check=True)
assert subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()=='arm64'
(out/'SHA256SUMS').write_text(hashlib.sha256(binary.read_bytes()).hexdigest()+'  hp-m1217-pclm\n')
print(binary)

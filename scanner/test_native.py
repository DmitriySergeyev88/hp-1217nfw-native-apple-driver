"""Synthetic offline fixtures only. Never contacts hardware or uses personal scans."""
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parent

def record(command,payload=b''):
    return struct.pack('>8I',0x41535001,command,0,0,0,len(payload),0,0)+payload

def fixture(adf=False,pages=1):
    settings=[0]*25;settings[3]=300;settings[14]=0x200 if adf else 0x100;settings[18]=8
    parts=[record(9,struct.pack('>25I',*settings)),record(10)]
    for page in range(pages):
        # 16 pixels, 24 RGB rows in B/R/G plane order; each page is distinguishable.
        pixels=b''.join(bytes([(row+page*40)%256])*16+bytes([120+page])*16+bytes([200-row])*16 for row in range(24))
        band=struct.pack('>6I',12 if adf else 10,0,72,1,16,16)+pixels
        parts.extend([record(11),record(5,band),record(14)])
    return b''.join(parts+[record(13),record(12)])

class NativeTests(unittest.TestCase):
    def test_transport_and_decoder(self):
        for name in ['marvell_probe','decode_capture']:
            subprocess.run([str(ROOT/'build'/name),'--test'],check=True)
    def test_single_multi_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for adf,count in [(False,1),(True,2)]:
                source=root/f'in-{count}.asp';source.write_bytes(fixture(adf,count));base=root/f'out-{count}'
                cmd=[str(ROOT/'build/decode_capture'),str(source),str(base)]
                self.assertEqual(subprocess.run(cmd,capture_output=True).returncode,0)
                pdf=base.with_suffix('.pdf');before=pdf.read_bytes()
                self.assertEqual(subprocess.run(cmd,capture_output=True).returncode,1)
                self.assertEqual(pdf.read_bytes(),before)
                if count==2:
                    self.assertNotEqual((root/'out-2-page-001.png').read_bytes(),(root/'out-2-page-002.png').read_bytes())
    def test_bad_streams(self):
        good=fixture();bad_size=bytearray(good);struct.pack_into('>I',bad_size,20,0xffffffff)
        bad_row=bytearray(good);pos=0
        while struct.unpack_from('>I',good,pos+4)[0]!=5:pos+=32+struct.unpack_from('>I',good,pos+20)[0]
        struct.pack_into('>I',bad_row,pos+36,1)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'input.asp'
            for i,bad in enumerate([b'',good[:-1],b'BAD!'+good[4:],bad_size,bad_row]):
                source.write_bytes(bad);base=root/f'bad-{i}'
                self.assertEqual(subprocess.run([str(ROOT/'build/decode_capture'),str(source),str(base)],capture_output=True).returncode,1)
                self.assertEqual(list(root.glob(f'bad-{i}.*')),[])
    def test_unsupported_before_network(self):
        self.assertEqual(subprocess.run([str(ROOT/'build/marvell_capture'),'127.0.0.1','/invalid/output','600','adf','color','a4'],capture_output=True).returncode,2)
if __name__=='__main__':unittest.main()

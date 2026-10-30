"""Offline synthetic fixtures. No queue creation or network access."""
import io,os,re,struct,subprocess,sys,tempfile,time,unittest
from pathlib import Path
from PIL import Image
from pypdf import PdfReader, PdfWriter
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent))
from test_printing import urf,header,packets
# Narrow firmware reader projection, 20200618 addresses 2821ee90..2821ef55.
def strip_dispatch(dictionary, inherited_length=0):
    state = dict(Length=inherited_length, Width=0, Height=0,
                 BitsPerComponent=0, Filter='FlateDecode', ColorSpace=None)
    pos = 0
    while (slash := dictionary.find(b'/', pos)) >= 0:
        pos = slash + 1
        token = re.match(rb'[A-Za-z]+', dictionary[pos:])
        if not token:
            continue
        key = token[0].decode()
        pos += len(token[0])
        if key in ('Length', 'Width', 'Height', 'BitsPerComponent'):
            while pos < len(dictionary) and dictionary[pos] in b' \r\n\t\f\0':
                pos += 1
            number = re.match(rb'[0-9]+', dictionary[pos:])
            if not number:
                raise ValueError('numeric field missing')
            state[key] = int(number[0])
            # Reader consumes the terminating byte AND the following byte.
            pos += len(number[0]) + 2
        elif key in ('DCTDecode', 'FlateDecode', 'RunLengthDecode'):
            state['Filter'] = key
        elif key in ('DeviceGray', 'DeviceRGB'):
            state['ColorSpace'] = key
        if state['BitsPerComponent'] == 8 and state['Length']:
            return state
    raise ValueError('strip never dispatched')

BIN=ROOT/'build/hp-m1217-pclm'
class FilterTests(unittest.TestCase):
 def convert(self,data):
  return subprocess.run([str(BIN)],input=data,capture_output=True,timeout=30)
 def test_pages_pixels_and_firmware_fields(self):
  rows=[bytes((x+y)%256 for x in range(250)) for y in range(260)]
  result=self.convert(urf([rows,rows[::-1]]));self.assertEqual(result.returncode,0,result.stderr)
  doc=PdfReader(io.BytesIO(result.stdout),strict=True);self.assertEqual(len(doc.pages),2)
  for page,original in zip(doc.pages,[rows,rows[::-1]]):
   self.assertEqual(tuple(page.mediabox),(0,0,30,32))
   raster=[]
   for ref in page['/Resources']['/XObject'].values():
    obj=ref.get_object();off=doc.xref[0][ref.idnum]
    attrs=result.stdout[off:result.stdout.index(b'\nstream\n',off)]
    state=strip_dispatch(attrs,len(page.get_contents().get_data()))
    self.assertEqual((state['Width'],state['Height'],state['Length'],state['Filter']),
                     (obj['/Width'],obj['/Height'],len(obj._data),'DCTDecode'))
    im=Image.open(io.BytesIO(obj._data));im.load()
    self.assertEqual(im.mode,'L');self.assertFalse(im.info.get('progressive',False))
    raster.extend(im.tobytes())
   raw=b''.join(original);self.assertEqual(len(raw),len(raster))
   self.assertLess(sum(abs(a-b) for a,b in zip(raw,raster))/len(raw),3)
  self.assertTrue(result.stdout.endswith(b'%%EOF\n'))
 def test_repeated_rows_across_strip_boundary(self):
  data=b'UNIRAST\0'+struct.pack('>I',1)+header(25,256)+b'\xff'+packets(b'\x7f'*25)
  p=self.convert(data);self.assertEqual(p.returncode,0,p.stderr)
  page=PdfReader(io.BytesIO(p.stdout)).pages[0]
  for ref in page['/Resources']['/XObject'].values():
   self.assertEqual(set(Image.open(io.BytesIO(ref.get_object()._data)).tobytes()),{127})
 def test_malformed_emits_no_document(self):
  good=urf([[b'\x80'*25]*130])
  bad=[b'',good[:-1],good[:12],good[:12]+header(5101,1),good[:12]+header(25,1,300),
       b'UNIRAST\0'+struct.pack('>I',2)+good[12:],good[:12]+header(25,1)+b'\x01'+packets(b'X'*25)]
  for data in bad:
   p=self.convert(data);self.assertNotEqual(p.returncode,0);self.assertEqual(p.stdout,b'')
 def test_cups_file_abi(self):
  with tempfile.TemporaryDirectory() as d:
   file=Path(d)/'input.urf';file.write_bytes(urf([[b'\xff'*25]*25]))
   p=subprocess.run([str(BIN),'1','test','fixture','1','media=A4',str(file)],capture_output=True,timeout=30)
   self.assertEqual(p.returncode,0,p.stderr);self.assertEqual(len(PdfReader(io.BytesIO(p.stdout)).pages),1)
 def test_pdf_with_real_cups_final_mime(self):
  with tempfile.TemporaryDirectory() as d:
   file=Path(d)/'fixture.pdf';writer=PdfWriter();writer.add_blank_page(width=595.2756,height=841.8898)
   with file.open('wb') as out:writer.write(out)
   env=dict(os.environ,CONTENT_TYPE='application/pdf',FINAL_CONTENT_TYPE='application/PCLm',PPD=str(ROOT/'HP-M1217-PCLm.ppd'))
   for via_file in (False,True):
    args=[str(BIN),'1','test','fixture','1','media=A4 printer-resolution=600dpi']
    if via_file:args.append(str(file))
    p=subprocess.run(args,input=None if via_file else file.read_bytes(),capture_output=True,env=env,timeout=30)
    self.assertEqual(p.returncode,0,p.stderr)
    self.assertIn(b'isURF=YES',p.stderr)
    page=PdfReader(io.BytesIO(p.stdout),strict=True).pages[0]
    self.assertEqual(tuple(page.mediabox),(0,0,596,842))
    images=page['/Resources']['/XObject']
    self.assertEqual(images['/Image0']['/Width'],4960)
    self.assertEqual(sum(ref.get_object()['/Height'] for ref in images.values()),7015)
 def test_invalid_pdf_child_failure_emits_nothing(self):
  env=dict(os.environ,CONTENT_TYPE='application/pdf',FINAL_CONTENT_TYPE='application/PCLm',PPD=str(ROOT/'HP-M1217-PCLm.ppd'))
  p=subprocess.run([str(BIN),'1','test','fixture','1','media=A4'],input=b'broken PDF',capture_output=True,env=env,timeout=30)
  self.assertNotEqual(p.returncode,0);self.assertEqual(p.stdout,b'')
 def test_cancel_pdf_pipeline(self):
  env=dict(os.environ,CONTENT_TYPE='application/pdf',FINAL_CONTENT_TYPE='application/PCLm',PPD=str(ROOT/'HP-M1217-PCLm.ppd'))
  p=subprocess.Popen([str(BIN),'1','test','fixture','1','media=A4'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
  try:
   time.sleep(0.1);p.terminate();out,err=p.communicate(timeout=5)
   self.assertNotEqual(p.returncode,0);self.assertEqual(out,b'')
  finally:
   if p.poll() is None:p.kill();p.communicate(timeout=5)
if __name__=='__main__':unittest.main()

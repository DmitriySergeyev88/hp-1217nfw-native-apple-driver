"""Synthetic offline tests only; no CUPS queue or printer access."""
from pathlib import Path
import os,random,signal,struct,subprocess,tempfile,time,unittest
from prepare import prepare
ROOT=Path(__file__).resolve().parent
BIN=ROOT/'build/hp-m1217-urf'

def header(w,h,dpi=600):
    p=bytearray(32);p[0]=8;p[2]=1
    struct.pack_into('>III',p,12,w,h,dpi)
    return bytes(p)
def packets(row):
    # Deliberately simple valid reference encoding: literal packets only.
    out=bytearray()
    for start in range(0,len(row),128):
        chunk=row[start:start+128];out+=bytes([257-len(chunk) if len(chunk)>1 else 0])+chunk
    return bytes(out)
def urf(pages):
    return b'UNIRAST\0'+struct.pack('>I',len(pages))+b''.join(header(len(rows[0]),len(rows))+b''.join(b'\0'+packets(row) for row in rows) for rows in pages)
def unpack(data):
    assert data[:8]==b'UNIRAST\0';pos=12;pages=[]
    while pos<len(data):
        hdr=data[pos:pos+32];pos+=32;w,h,dpi=struct.unpack_from('>III',hdr,12);rows=[]
        while len(rows)<h:
            repeats=data[pos]+1;pos+=1;row=bytearray()
            while len(row)<w:
                c=data[pos];pos+=1
                if c==128:row+=b'\xff'*(w-len(row))
                elif c<128:row+=bytes([data[pos]])*(c+1);pos+=1
                else:
                    n=257-c;row+=data[pos:pos+n];pos+=n
            assert len(row)==w;rows.extend([bytes(row)]*repeats)
        assert len(rows)==h;pages.append((hdr,rows))
    return pages

def optimum(row):
    dp=[0]+[10**6]*len(row)
    for end in range(1,len(row)+1):
        for n in range(1,min(128,end)+1):
            piece=row[end-n:end]
            if len(set(piece))==1:dp[end]=min(dp[end],dp[end-n]+2)
            if n>=2:dp[end]=min(dp[end],dp[end-n]+n+1)
    return dp[-1]

class PrintingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory();cls.work=Path(cls.tmp.name)
        # Independent decoder: the installed system libcups, not our parser.
        source=cls.work/'decode.c'
        source.write_text('''#include <cups/raster.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc,char**argv){(void)argv;cups_raster_t*r=cupsRasterOpen(0,CUPS_RASTER_READ);cups_page_header2_t h;
cups_raster_t*out=argc==2?cupsRasterOpen(1,CUPS_RASTER_WRITE_APPLE):NULL;
if(!r)return 1;unsigned pages=0;
while(cupsRasterReadHeader2(r,&h)){if(h.cupsWidth>12000||h.cupsBytesPerLine!=h.cupsWidth||h.HWResolution[0]!=600||h.cupsBitsPerPixel!=8||h.cupsColorSpace!=CUPS_CSPACE_SW)return 2;
if(out&&!cupsRasterWriteHeader2(out,&h))return 7;unsigned char*row=malloc(h.cupsWidth);if(!row)return 3;
for(unsigned y=0;y<h.cupsHeight;y++){if(cupsRasterReadPixels(r,row,h.cupsWidth)!=h.cupsWidth)return 4;if(out){if(cupsRasterWritePixels(out,row,h.cupsWidth)!=h.cupsWidth)return 8;}else if(fwrite(row,1,h.cupsWidth,stdout)!=h.cupsWidth)return 5;}free(row);pages++;}
cupsRasterClose(r);if(out)cupsRasterClose(out);return pages?0:6;}''')
        cls.decoder=cls.work/'decode'
        subprocess.run(['clang','-Wno-deprecated-declarations',str(source),'-lcups','-o',str(cls.decoder)],check=True)
        # PDF is synthetic: vectors, tiny text and a 100mm reference line.
        source=cls.work/'fixture.m';source.write_text('''#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
int main(int argc,char**argv){@autoreleasepool{if(argc!=2)return 1;
NSURL*u=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];CGRect box=CGRectMake(0,0,595.2756,841.8898);
CGContextRef c=CGPDFContextCreateWithURL((__bridge CFURLRef)u,&box,NULL);if(!c)return 2;
for(int page=0;page<2;page++){CGPDFContextBeginPage(c,NULL);
for(int i=0;i<256;i++){CGContextSetGrayFillColor(c,i/255.0,1);CGContextFillRect(c,CGRectMake(36+i*2,500,2,100));}
CGContextSetGrayStrokeColor(c,0,1);CGContextSetLineWidth(c,.12);CGContextMoveToPoint(c,36,400);CGContextAddLineToPoint(c,36+100*72/25.4,400);CGContextStrokePath(c);
CTFontRef f=CTFontCreateWithName(CFSTR("Helvetica"),4,NULL);NSAttributedString*s=[[NSAttributedString alloc]initWithString:@"600 dpi small text 0123456789" attributes:@{(__bridge NSString*)kCTFontAttributeName:(__bridge id)f}];CTLineRef l=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);CGContextSetTextPosition(c,36,700);CTLineDraw(l,c);CFRelease(l);CFRelease(f);CGPDFContextEndPage(c);}
CGPDFContextClose(c);CGContextRelease(c);return 0;}}''')
        cls.fixture=cls.work/'fixture'
        subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','CoreGraphics','-framework','CoreText',str(source),'-o',str(cls.fixture)],check=True)
    @classmethod
    def tearDownClass(cls):cls.tmp.cleanup()
    def run_filter(self,data):return subprocess.run([str(BIN)],input=data,capture_output=True,timeout=60)
    def test_optimum_and_system_decoder(self):
        rng=random.Random(1217)
        rows=[bytes(rng.randrange(8) for _ in range(n)) for n in [1,2,3,127,128,129,255,256]]
        rows += [b'\0'*129,b'\xff'*256,bytes([1,2,2,3])*70,bytes(range(256))]
        for row in rows:
            original=urf([[row]]);r=self.run_filter(original);self.assertEqual(r.returncode,0,r.stderr)
            self.assertEqual(unpack(r.stdout),unpack(original))
            self.assertEqual(len(r.stdout)-45,optimum(row))
            self.assertEqual(subprocess.check_output([str(self.decoder)],input=r.stdout),row)
    def test_improves_greedy_packet_boundaries(self):
        rows=[bytes([1,2,2,3])*1240]*8
        original=subprocess.check_output([str(self.decoder),'recode'],input=urf([rows]))
        r=self.run_filter(original);self.assertEqual(r.returncode,0)
        self.assertEqual(unpack(r.stdout),unpack(original));self.assertLess(len(r.stdout),len(original))
        (ROOT/'build/packet-comparison.txt').write_text(f'Synthetic short-run pattern: system CUPS URF {len(original)} bytes; native {len(r.stdout)} bytes, identical pixels. This pattern is not a photograph.\n')
    def test_repeat_pages_metadata(self):
        pages=[[b'\x42'*19]*513,[bytes(range(71))]*257]
        original=bytearray(urf(pages));original[12+3]=5;original[12+5]=2
        r=self.run_filter(original);self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(unpack(r.stdout),unpack(original))
        self.assertEqual(subprocess.check_output([str(self.decoder)],input=r.stdout),b''.join(b''.join(p) for p in pages))
        self.assertLess(len(r.stdout),len(original))
    def test_reject_malformed(self):
        good=urf([[b'123456']]);bad_count=good[:8]+struct.pack('>I',2)+good[12:]
        cases=[b'',b'bad',good[:44],good[:-1],good+b'x',bad_count,
               good[:12]+header(6,1,300)+good[44:],good[:12]+header(12001,1)+good[44:],
               good[:44]+b'\xff'+good[45:],good[:44]+b'\0\x7f\0']
        for data in cases:self.assertNotEqual(self.run_filter(data).returncode,0)
        for offset,value in [(12,1),(13,1)]:
            data=bytearray(good);data[offset]=value;self.assertNotEqual(self.run_filter(data).returncode,0)
    def test_white_suffix_unknown_page_count(self):
        data=b'UNIRAST\0'+bytes(4)+header(100,1)+b'\0\x80'
        r=self.run_filter(data);self.assertEqual(r.returncode,0);self.assertEqual(unpack(r.stdout),unpack(data))
    def test_filter_abi_and_broken_pipe(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'input';p.write_bytes(urf([[b'abc']]))
            r=subprocess.run([str(BIN),'1','user','private-title','1','',str(p)],capture_output=True)
            self.assertEqual(r.returncode,0);self.assertNotIn(b'private-title',r.stderr)
        rd,wr=os.pipe();os.close(rd)
        try:r=subprocess.run([str(BIN)],input=urf([[b'abc']]),stdout=wr,stderr=subprocess.PIPE)
        finally:os.close(wr)
        self.assertNotEqual(r.returncode,0)
    def test_cancellation_blocked_input(self):
        process=subprocess.Popen([str(BIN)],stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        try:
            time.sleep(.05);process.send_signal(signal.SIGTERM)
            self.assertNotEqual(process.wait(timeout=3),0)
        finally:
            if process.poll() is None:process.kill();process.wait()
            process.stdin.close();process.stderr.close()
    def test_photo_noise_full_600dpi_page(self):
        rng=random.Random(1217)
        rows=[rng.randbytes(4960) for _ in range(7015)]
        source=urf([rows]);start=time.monotonic();r=self.run_filter(source);elapsed=time.monotonic()-start
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(unpack(r.stdout),unpack(source));self.assertLessEqual(len(r.stdout),len(source))
        with (ROOT/'build/noise-comparison.txt').open('w') as out:
            out.write(f'Synthetic noise A4 4960x7015 600 dpi: literal URF {len(source)} bytes; native {len(r.stdout)} bytes; subprocess encoding {elapsed:.3f}s. Not a printer speed measurement.\n')
    def test_full_page_and_pdf_pipeline(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp);pdf=tmp/'fixture.pdf';subprocess.run([str(self.fixture),str(pdf)],check=True)
            ppd=(ROOT/'HP-M1217-Native.ppd').read_text()
            # Point the final CUPS filter to this local build; no installation required.
            ppd=ppd.replace('/Library/Printers/HPNative1217/Filters/hp-m1217-urf',str(BIN))
            (tmp/'driver.ppd').write_text(ppd)
            cmd=['/usr/sbin/cupsfilter','-p',str(tmp/'driver.ppd'),'-i','application/pdf','-m','printer/offline','-e','-o','media=A4',str(pdf)]
            r=subprocess.run(cmd,capture_output=True,timeout=120)
            self.assertEqual(r.returncode,0,r.stderr.decode(errors='replace'));self.assertIn(b'HP Native URF page=',r.stderr)
            pages=unpack(r.stdout);self.assertEqual(len(pages),2)
            self.assertEqual(struct.unpack_from('>III',pages[0][0],12),(4960,7015,600))
            target=tmp/'offline.urf';prepare(pdf,target,'A4')
            self.assertEqual(unpack(target.read_bytes()),pages)
            # Compare directly with Apple's original URF, before our encoder.
            baseline=ppd.replace(str(BIN),'-');(tmp/'baseline.ppd').write_text(baseline)
            original=subprocess.check_output(['/usr/sbin/cupsfilter','-p',str(tmp/'baseline.ppd'),'-i','application/pdf','-m','image/urf','-o','media=A4',str(pdf)],stderr=subprocess.DEVNULL)
            self.assertEqual(unpack(original),pages)
            self.assertLessEqual(len(r.stdout),len(original))
            (ROOT/'build/offline-comparison.txt').write_text(f'Synthetic 2-page A4 PDF: Apple URF {len(original)} bytes; native URF {len(r.stdout)} bytes. Headers and every pixel identical.\n')
            before=target.read_bytes()
            with self.assertRaises(FileExistsError):prepare(pdf,target,'A4')
            self.assertEqual(target.read_bytes(),before)
    def test_letter_landscape_matches_native(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp);pdf=tmp/'fixture.pdf';subprocess.run([str(self.fixture),str(pdf)],check=True)
            ppd=(ROOT/'HP-M1217-Native.ppd').read_text().replace('/Library/Printers/HPNative1217/Filters/hp-m1217-urf',str(BIN))
            for name,text in [('driver',ppd),('baseline',ppd.replace(str(BIN),'-'))]:(tmp/(name+'.ppd')).write_text(text)
            results=[]
            for name in ['driver','baseline']:
                r=subprocess.run(['/usr/sbin/cupsfilter','-p',str(tmp/(name+'.ppd')),'-i','application/pdf','-m','printer/offline','-e','-o','media=Letter','-o','orientation-requested=4',str(pdf)],capture_output=True,timeout=120)
                self.assertEqual(r.returncode,0,r.stderr);results.append(unpack(r.stdout))
            self.assertEqual(results[0],results[1]);self.assertEqual(len(results[0]),2)
            self.assertEqual(struct.unpack_from('>III',results[0][0][0],12),(5100,6600,600))
    def test_ppd(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'driver.ppd'
            path.write_text((ROOT/'HP-M1217-Native.ppd').read_text().replace('/Library/Printers/HPNative1217/Filters/hp-m1217-urf',str(BIN)))
            subprocess.run(['/usr/bin/cupstestppd','-I','filters','-q',str(path)],check=True)
    def test_installer(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp);expanded=tmp/'expanded'
            subprocess.run(['pkgutil','--expand-full',str(ROOT/'build/HP-M1217-Native-Print-0.1.0-arm64.pkg'),str(expanded)],check=True)
            bom=subprocess.check_output(['lsbom',str(expanded/'Bom')],text=True)
            entry=next(line for line in bom.splitlines() if line.startswith('./Library/Printers/HPNative1217/Filters/hp-m1217-urf\t'))
            self.assertEqual(entry.split('\t')[1:3],['100755','0/0'])
            payload=expanded/'Payload';allowed='Library/Printers/HPNative1217/'
            files=[str(p.relative_to(payload)) for p in payload.rglob('*') if p.is_file()]
            self.assertEqual(set(files),{allowed+x for x in ['Filters/hp-m1217-urf','HP-M1217-Native.ppd','LICENSE','README.md']})
            pre=expanded/'Scripts/preinstall';target=tmp/'target';target.mkdir()
            args=['sh',str(pre),'package','/',str(target)]
            self.assertEqual(subprocess.run(args,capture_output=True).returncode,0)
            path=target/allowed;path.parent.mkdir(parents=True);path.write_text('keep')
            self.assertNotEqual(subprocess.run(args,capture_output=True).returncode,0);self.assertEqual(path.read_text(),'keep')
            path.unlink();path.symlink_to(tmp/'missing')
            self.assertNotEqual(subprocess.run(args,capture_output=True).returncode,0)
if __name__=='__main__':unittest.main()

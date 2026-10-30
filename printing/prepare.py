"""PDF -> native URF file, offline only. No queue or printer access."""
from pathlib import Path
import argparse,subprocess,tempfile,os
root=Path(__file__).resolve().parent

def prepare(source,target,media):
    # Render exactly once using Apple's existing profile/geometry, then lossless encode.
    ppd=(root/'HP-M1217-Native.ppd').read_text()
    ppd='\n'.join(x for x in ppd.splitlines() if not x.startswith('*cupsFilter'))
    ppd+='\n*cupsFilter2: "image/urf image/urf 10 -"\n'
    with tempfile.TemporaryDirectory(prefix='hp-print-') as tmp:
        tmp=Path(tmp);(tmp/'render.ppd').write_text(ppd)
        with (tmp/'render.urf').open('wb') as out:
            subprocess.run(['/usr/sbin/cupsfilter','-p',str(tmp/'render.ppd'),'-i','application/pdf','-m','image/urf',
                '-o','media='+media,'-o','printer-resolution=600dpi',str(source.resolve())],stdout=out,check=True,timeout=300)
        # Stage next to destination; link publishes atomically without overwriting.
        fd,path=tempfile.mkstemp(prefix='.hp-urf-',dir=target.parent)
        try:
            with os.fdopen(fd,'wb') as out,(tmp/'render.urf').open('rb') as inp:
                subprocess.run([str(root/'build/hp-m1217-urf')],stdin=inp,stdout=out,check=True,timeout=300)
                out.flush();os.fsync(out.fileno())
            os.link(path,target)
        finally:os.unlink(path)
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('pdf',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--media',choices=['A4','Letter'],default='A4');a=p.parse_args()
    if a.output.exists() or a.output.is_symlink():p.error('output already exists')
    prepare(a.pdf,a.output,a.media)

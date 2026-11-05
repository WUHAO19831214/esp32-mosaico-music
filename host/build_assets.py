"""Generate private 16-level alpha fonts and original icons on this Mac.

AFN1: <4sHHII> header, <IIHH> sorted glyph records, then RLE bytes.
Each RLE byte stores 4-bit alpha (high) and run length minus one (low).
The device reads individual glyphs from 256 KiB shards; it never loads a whole CJK atlas into RAM.
"""
from pathlib import Path
import math
import struct
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'app/assets'
OUT.mkdir(parents=True, exist_ok=True)
FONT = '/System/Library/Fonts/Hiragino Sans GB.ttc'
CHARS = sorted(set(chr(i) for i in range(32,127)) |
               set(chr(i) for i in range(0xa0,0x250)) |
               set(chr(i) for i in range(0x3000,0x3100)) |
               set(chr(i) for i in range(0x4e00,0xa000)) |
               set('…·，。：“”！？（）《》、—'))

def rle(image):
    pixels = [(p+8)//17 for p in image.tobytes()]
    out = bytearray(); last = pixels[0]; count = 0
    for p in pixels:
        if p == last and count < 16:
            count += 1
        else:
            out.append(last*16+count-1); last=p; count=1
    out.append(last*16+count-1)
    return bytes(out)

def atlas(name, width, height, glyphs):
    records, data = bytearray(), bytearray()
    for cp, advance, image in sorted(glyphs, key=lambda item:item[0]):
        raw=rle(image)
        records.extend(struct.pack('<IIHH',cp,len(data),len(raw),advance))
        data.extend(raw)
    blob=struct.pack('<4sHHII',b'AFN1',width,height,len(glyphs),ord('?'))+records+data
    # Older factory HTTP servers interrupt large uploads. Keep every file small.
    chunk_size=256*1024
    assert 16+len(records)<=chunk_size
    stem=Path(name).stem
    for old in OUT.glob(stem+'-*.afn'):old.unlink()
    for i,start in enumerate(range(0,len(blob),chunk_size)):
        (OUT/f'{stem}-{i:03d}.afn').write_bytes(blob[start:start+chunk_size])
    print(f'{name}: {len(glyphs)} glyphs, {len(blob):,} bytes in {math.ceil(len(blob)/chunk_size)} shards')

def font_atlas(name,size,index,chars):
    f=ImageFont.truetype(FONT,size,index=index)
    w,h=size+4,size+8
    glyphs=[]
    for c in chars:
        im=Image.new('L',(w,h))
        ImageDraw.Draw(im).text((1,-3),c,font=f,fill=255)
        glyphs.append((ord(c),math.ceil(f.getlength(c))+1,im))
    atlas(name,w,h,glyphs)

font_atlas('body-28.afn',28,2,CHARS)
font_atlas('detail-22.afn',22,2,CHARS)
font_atlas('title-34.afn',34,2,CHARS)

# Original, supersampled UI icons. The order is shared with render.lua.
names=['speaker','bluetooth','mic','check','search','chevron','close',
       'play','pause','prev','next','songs','account','settings','minus','plus','monitor']
glyphs=[]
for i,name in enumerate(names):
    scale=4
    im=Image.new('L',(28*scale,28*scale));d=ImageDraw.Draw(im)
    def line(points,width=2.2):d.line([(round(x*scale),round(y*scale)) for x,y in points],fill=255,width=round(width*scale),joint='curve')
    def rect(box):d.rounded_rectangle(tuple(round(x*scale) for x in box),radius=scale,fill=255)
    def ellipse(box,fill=None,width=2.2):d.ellipse(tuple(round(x*scale)for x in box),fill=fill,outline=255,width=round(width*scale))
    def arc(box,start,end):d.arc(tuple(round(x*scale)for x in box),start,end,fill=255,width=round(2.1*scale))
    def poly(points):d.polygon([(round(x*scale),round(y*scale))for x,y in points],fill=255)
    if name=='speaker':
        poly([(3,11),(8,11),(14,6),(14,22),(8,17),(3,17)])
        arc((12,8,23,20),300,60);arc((12,4,28,24),305,55)
    elif name=='bluetooth':line([(7,7),(21,20),(14,26),(14,2),(21,8),(7,21)])
    elif name=='mic':
        d.rounded_rectangle((10*scale,2*scale,18*scale,18*scale),4*scale,fill=255)
        arc((6,7,22,23),0,180);line([(6,13),(6,15)]);line([(22,13),(22,15)])
        line([(14,23),(14,27)]);line([(10,27),(18,27)])
    elif name=='check':line([(5,14),(11,20),(23,7)],2.8)
    elif name=='search':ellipse((3,3,19,19));line([(18,18),(25,25)],2.6)
    elif name=='chevron':line([(10,5),(19,14),(10,23)],2.6)
    elif name=='close':line([(6,6),(22,22)]);line([(22,6),(6,22)])
    elif name=='play':poly([(8,4),(24,14),(8,24)])
    elif name=='pause':rect((7,5,11,23));rect((17,5,21,23))
    elif name in ('prev','next'):
        if name=='prev':rect((5,6,8,22));poly([(22,5),(9,14),(22,23)])
        else:rect((20,6,23,22));poly([(6,5),(19,14),(6,23)])
    elif name=='songs':
        line([(10,21),(10,6),(23,3),(23,18)]);line([(10,10),(23,7)])
        ellipse((3,18,10,25),255);ellipse((16,15,23,22),255)
    elif name=='account':ellipse((9,3,19,13));arc((4,16,24,34),180,360)
    elif name=='settings':
        ellipse((5,5,23,23));ellipse((11,11,17,17))
        for x,y,xx,yy in [(14,1,14,5),(14,23,14,27),(1,14,5,14),(23,14,27,14),(4,4,7,7),(21,21,24,24),(4,24,7,21),(21,7,24,4)]:line([(x,y),(xx,yy)],2.5)
    elif name in ('minus','plus'):
        line([(6,14),(22,14)],2.8)
        if name=='plus':line([(14,6),(14,22)],2.8)
    elif name=='monitor':
        d.rounded_rectangle((3*scale,4*scale,25*scale,20*scale),2*scale,outline=255,width=2*scale)
        line([(14,20),(14,25)]);line([(9,25),(19,25)])
    glyphs.append((0xe000+i,28,im.resize((28,28),Image.Resampling.LANCZOS)))
atlas('icons.afn',28,28,glyphs)

icon=Image.new('RGB',(768,768),'#ec4141');d=ImageDraw.Draw(icon)
d.ellipse((92,92,676,676),fill='#ffffff')
d.ellipse((176,176,592,592),outline='#ec4141',width=14)
d.ellipse((280,280,488,488),fill='#ec4141')
d.ellipse((364,364,404,404),fill='#ffffff')
icon.resize((192,192),Image.Resampling.LANCZOS).save(OUT/'icon.jpg',quality=95)

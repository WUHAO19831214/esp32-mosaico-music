"""Create a private on-device CJK font from the Mac's installed system font."""
from pathlib import Path
import math
import struct
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT='/System/Library/Fonts/Hiragino Sans GB.ttc'
font = ImageFont.truetype(FONT,28,index=2)
chars = sorted(set(chr(i) for i in range(32,127)) | set(chr(i)for i in range(0xa0,0x250)) | set(chr(i)for i in range(0x3000,0x3100)) | set(chr(i) for i in range(0x4e00,0xa000)) | set('…·，。：“”！？（）《》、—'))
width, height = 32,36
groups=[[] for _ in range(7)]
for c in chars:
    groups[1+(ord(c)-0x4e00)//3500 if 0x4e00<=ord(c)<0xa000 else 0].append(c)
total=0
for index,group in enumerate(groups):
    group=sorted(set(group+['?']))
    records, bitmaps = bytearray(), bytearray()
    for c in group:
        image = Image.new('L',(width,height))
        ImageDraw.Draw(image).text((1,-3),c,font=font,fill=255,stroke_width=0)
        mask=image.point(lambda p:255 if p>=105 else 0).convert('1')
        records.extend(struct.pack('<IIhhhHH',ord(c),len(bitmaps),math.ceil(font.getlength(c))+1,0,0,width,height))
        bitmaps.extend(mask.tobytes())
    header=struct.pack('<4shhhHII',b'DFN1',height,0,width,0,len(group),ord('?'))
    (ROOT/f'app/assets/cjk-{index}.dfn').write_bytes(header+records+bitmaps)
    total+=len(header+records+bitmaps)
old=ROOT/'app/assets/cjk-22.dfn'
if old.exists():old.unlink()
title_chars=sorted(set(chr(i)for i in range(32,127))|set('…')|set(c for c in (ROOT/'app/scripts/render.lua').read_text()if 0x4e00<=ord(c)<0xa000))
f=ImageFont.truetype(FONT,34,index=2);records,bitmaps=bytearray(),bytearray()
for c in title_chars:
    im=Image.new('L',(40,44));ImageDraw.Draw(im).text((1,-3),c,font=f,fill=255,stroke_width=0)
    records.extend(struct.pack('<IIhhhHH',ord(c),len(bitmaps),math.ceil(f.getlength(c))+1,0,0,40,44));bitmaps.extend(im.point(lambda p:255 if p>=105 else 0).convert('1').tobytes())
(ROOT/'app/assets/title-34.dfn').write_bytes(struct.pack('<4shhhHII',b'DFN1',44,0,40,0,len(title_chars),ord('?'))+records+bitmaps)
icon=Image.new('RGB',(192,192),(16,23,17));d=ImageDraw.Draw(icon)
d.ellipse((20,20,172,172),fill=(37,48,39),outline=(196,223,170),width=4)
for radius in [64,55,46]:d.ellipse((96-radius,96-radius,96+radius,96+radius),outline=(70,82,68),width=2)
d.ellipse((67,67,125,125),fill=(223,198,154));d.ellipse((89,89,103,103),fill=(16,23,17))
icon.save(ROOT/'app/assets/icon.jpg',quality=92)
print(f'Created 7 CJK font pages below the 4096-glyph firmware limit: {len(chars)} glyphs, {total} bytes')

"""Compose clearly labelled public illustrations from the actual Lua previews."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/images';OUT.mkdir(parents=True,exist_ok=True)
FONT='/System/Library/Fonts/Hiragino Sans GB.ttc'
label=ImageFont.truetype(FONT,32,index=2)
small=ImageFont.truetype(FONT,23,index=0)
title=ImageFont.truetype(FONT,52,index=2)
canvas=Image.new('RGB',(1680,790),'#f6f6f6');d=ImageDraw.Draw(canvas)
d.text((50,26),'MOSAICO MUSIC',font=title,fill='#202124')
d.text((52,98),'网易云音乐 · ESP32-S31 触屏终端 × macOS 音频助手',font=label,fill='#ec4141')
for i,(source,name)in enumerate([('now-data.png','01  正在播放'),('settings-data.png','02  输出与音量'),('search-data.png','03  中文拼音搜歌')]):
    x=50+i*545
    image=Image.open(ROOT/'evidence'/source).convert('RGB')
    canvas.paste(image,(x,174))
    d.text((x,692),name,font=label,fill='#202124')
d.text((50,748),'真实 Lua 渲染器生成的界面预览，使用演示数据；非硬件实拍',font=small,fill='#747880')
canvas.save(OUT/'overview.png',optimize=True)
for source,name in [('settings-data.png','settings.png'),('search-data.png','chinese-input.png'),('bluetooth-data.png','bluetooth.png'),('songs-data.png','songs.png')]:
    image=Image.open(ROOT/'evidence'/source).convert('RGB')
    image.resize((960,960),Image.Resampling.NEAREST).save(OUT/name,optimize=True)
print('Created five public illustrations without personal account screenshots')

from pathlib import Path
import struct
from PIL import Image, ImageDraw
from lupa.lua54 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
(ROOT/'evidence').mkdir(exist_ok=True)
lua=LuaRuntime(unpack_returned_tuples=True)
# Compile every deployed file, including platform-dependent jobs.
for p in (ROOT/'app/scripts').glob('*.lua'):
    lua.execute('assert(load(...))',p.read_text())
model=lua.execute((ROOT/'app/scripts/model.lua').read_text())
model.dictionary=lua.execute((ROOT/'app/scripts/pinyin_dict.lua').read_text())
s=model.new()
assert model.hit(s,450,22)=='exit'
model.action(s,'search');assert s.page=='search'
for c in 'zhou':model.action(s,'letter:'+c)
assert model.candidates(s)[1]=='周'
model.action(s,'candidate:1');assert s.query=='周' and s.composition==''
for c in 'jie':model.action(s,'letter:'+c)
model.action(s,'candidate:1');assert s.query=='周杰'
for c in 'lun':model.action(s,'letter:'+c)
model.action(s,'candidate:1');assert s.query=='周杰伦'
model.action(s,'backspace');assert s.query=='周杰'
model.action(s,'mode');model.action(s,'letter:A');assert s.query=='周杰a'
assert model.action(s,'submit').q=='周杰a' and s.page=='songs'
assert model.truncate('周杰伦的歌',4)=='周杰伦…'
assert not model.linked(s,0)

class Screen:
    def __init__(self):
        self.im=Image.new('RGB',(480,480));self.d=ImageDraw.Draw(self.im)
        # Keep binary strings inside Lua; pass byte values across Lupa's UTF-8 boundary.
        self.blit=lua.eval('function(draw)return function(_,x,y,raw,opts)draw(x,y,{raw:byte(1,#raw)},opts)end end')(self.blit_bytes)
    def blit_bytes(self,x,y,raw,opts):
        assert opts['format']=='rgb565'
        data=bytes(raw[i] for i in range(1,len(raw)+1));w=opts['width'];h=opts['height']
        assert len(data)==w*h*2 and isinstance(x,int) and isinstance(y,int)
        pixels=[]
        for (c,) in struct.iter_unpack('<H',data):
            r=c>>11;g=c>>5&63;b=c&31
            pixels.append((r*255//31,g*255//63,b*255//31))
        tile=Image.new('RGB',(w,h));tile.putdata(pixels);self.im.paste(tile,(x,y))
    def color(self,c):
        # Match the device's default RGB565 framebuffer, including flat fills.
        r=(c>>19)&31;g=(c>>10)&63;b=(c>>3)&31
        return(r*255//31,g*255//63,b*255//31)
    def begin(self,o):self.d.rectangle((0,0,480,480),fill=self.color(o['clear']))
    def fill_rect(self,x,y,w,h,c):
        assert all(isinstance(a,int)for a in(x,y,w,h));self.d.rectangle((x,y,x+w-1,y+h-1),fill=self.color(c))
    def fill_round_rect(self,x,y,w,h,r,c):
        assert all(isinstance(a,int)for a in(x,y,w,h,r));self.d.rounded_rectangle((x,y,x+w-1,y+h-1),r,fill=self.color(c))
    def fill_circle(self,x,y,r,c):self.d.ellipse((x-r,y-r,x+r,y+r),fill=self.color(c))
    def line(self,x,y,x1,y1,c):self.d.line((x,y,x1,y1),fill=self.color(c))
    def present(self):return True
render=lua.execute((ROOT/'app/scripts/render.lua').read_text())
render.init(lua.table_from({}),str(ROOT/'app'))
for name in ['body-28','detail-22','title-34']:
    data=b''.join(p.read_bytes() for p in sorted((ROOT/'app/assets').glob(name+'-*.afn')))
    magic,w,h,count,fallback=struct.unpack('<4sHHII',data[:16]);assert magic==b'AFN1'
    records=[struct.unpack_from('<IIHH',data,16+i*12) for i in range(count)]
    mapping={cp:(offset,length,advance) for cp,offset,length,advance in records}
    assert len(mapping)==count and all(ord(c) in mapping for c in '莫扎特周杰伦日本語')
    assert ord('?')==fallback
    for cp in [ord(c) for c in '莫扎特周杰伦WQgj?']:
        offset,length,advance=mapping[cp];raw=data[16+count*12+offset:16+count*12+offset+length]
        assert sum((b&15)+1 for b in raw)==w*h and advance>0
        assert any(0<(b>>4)<15 for b in raw), 'Font must retain intermediate alpha coverage'

screen=Screen();s=model.new()
for page in ['now','songs','search','account','lists','settings','bluetooth','outputs']:
    s.page=page;render.draw(screen,s,1000);screen.im.save(ROOT/f'evidence/{page}.png')
audio=lua.table_from({'host':'MacBook Air','message':'选择具体设备，连接后确认输出','selected':lua.table_from({'name':'MacBook Air 扬声器','uid':'builtin-air','target':'mac','available':True}),'outputs':lua.table_from([lua.table_from({'name':'MacBook Air 扬声器','uid':'builtin-air','builtin':True}),lua.table_from({'name':'USB audio CODEC','uid':'usb-demo'})]),'devices':lua.table_from([lua.table_from({'name':'蓝牙音箱','address':'11-22-33-44-55-66','connected':False,'paired':True}),lua.table_from({'name':'WH-1000XM4','address':'aa-bb-cc-dd-ee-ff','paired':True,'connected':False})])})
feed=lua.table_from({'target':'mac','status':'playing','volume':30,'profile':'音乐爱好者','error':'','lyric':'让音乐留在桌面','position':32,'audio':audio,'current':lua.table_from({'name':'莫扎特 摇篮曲','artist':'Wolfgang Amadeus Mozart','duration':216}),'results':lua.table_from([lua.table_from({'id':str(i),'name':f'歌曲 {i} — 测试长名称','artist':'艺术家'})for i in range(1,11)]),'lists':lua.table_from([])})
model.feed(s,feed,1000);assert model.linked(s,5000)and not model.linked(s,11000)
s.page='songs';assert model.hit(s,200,130)=='song:1'
assert model.action(s,'song:1').id=='1'and s.page=='now'
event=model.event(s,'song:2','ui-run-123',7)
assert event.id=='2' and event.event_id=='ui-run-123-7' and event.action=='select'
s.data.lists=lua.table_from([lua.table_from({'id':'playlist-456','name':'歌单'})])
event=model.event(s,'list:1','ui-run-123',8)
assert event.id=='playlist-456' and event.event_id=='ui-run-123-8' and event.action=='playlist'
event=model.event(s,'playlists','ui-run-123',9)
assert event.id is None and event.event_id=='ui-run-123-9'
event=model.event(s,'exit','ui-run-123',10)
assert event.exit and event.event_id is None
# Exercise the real receiver acknowledgement logic: a song ID must never be
# treated as the delivery ID, and the next queued tap must be delivered.
protocol=LuaRuntime(unpack_returned_tuples=True)
setup=protocol.execute('''
return function(source)
 local queues={music_events={{action='select',id='track-1',event_id='tap-1'},{action='playlist',id='list-2',event_id='tap-2'}}}
 local routes={};local app={}
 function app:post(path,fn)routes[path]=fn end
 function app:serve_forever()end
 local audio={poll=function()return{state='idle'}end,close=function()end}
 local modules={
  http_server={app=function()return app end},
  json={decode=function(v)return v end,encode=function()return '{}'end},
  storage={get_root_dir=function()return'/nand'end,join_path=function(...)return table.concat({...},'/')end,read_file=function()return{token='test'}end},
  thread={sync={queue_create=function()return true end,queue_send=function(name,v)queues[name]=queues[name]or{};table.insert(queues[name],v);return true end,queue_recv=function(name)local q=queues[name]or{};return table.remove(q,1)end}},
  system={time=function()return 123 end,millis=function()return 456 end},capability={}
 }
 require=function(name)return assert(modules[name],name)end
 dofile=function(path)assert(path:match('/audio.lua$'));return audio end
 assert(load(source))()
 return routes
end
''')
routes=setup((ROOT/'app/scripts/receiver.lua').read_text())
def sync(ack=None):
    data={'token':'test','data':protocol.table_from({})}
    if ack:data['ack']=ack
    return routes['/sync'](protocol.table_from({'body':protocol.table_from(data)}))['json']
assert sync().event.id=='track-1'
assert sync('track-1').event.event_id=='tap-1'  # Domain ID is not an ACK.
assert sync('tap-1').event.id=='list-2'
assert sync('tap-2').event is None
feed.results=lua.table_from([lua.table_from({'id':str(i),'name':f'歌曲 {i}','artist':'艺术家'})for i in range(1,11)]);feed.result_seq=2;s.await_result=None;model.feed(s,feed,1000);s.data.results=feed.results
s.page='songs';model.action(s,'nextpage');assert s.offset==3
model.action(s,'nextpage');model.action(s,'nextpage');assert s.offset==9
model.action(s,'backpage');assert s.offset==6
s.page='settings';assert model.hit(s,50,385) is None
assert model.action(s,model.hit(s,300,375)).value==20
s.page='outputs';assert model.action(s,model.hit(s,120,180)).uid=='builtin-air'
s.page='bluetooth';assert model.action(s,model.hit(s,120,180)).address=='11-22-33-44-55-66'
s.page='now';assert model.hit(s,100,395)=='prev'
s.query='周杰伦';s.composition='zhou';s.ime=True
for page in ['now','songs','search','account','settings','bluetooth','outputs']:
    s.page=page;render.draw(screen,s,1000);screen.im.save(ROOT/f'evidence/{page}-data.png')
s.page='account';s.data.profile='';s.qr=lua.table_from({'size':41.0,'bits':'01'*(41*41//2)+'0','message':'请在手机上确认登录'})
render.draw(screen,s,1000);screen.im.save(ROOT/'evidence/qr-layout.png')
model.feed(s,lua.table_from({'result_total':104.0,'result_offset':99.0,'results':lua.table_from([]),'page_size':3.0}),1000)
s.page='songs';event=model.action(s,'nextpage');assert event.action=='devicepage'and event.offset==102
model.feed(s,lua.table_from({'result_total':104.0,'result_offset':102.0,'results':lua.table_from([]),'page_size':3.0}),1000)
assert model.action(s,'nextpage').offset==102 and model.action(s,'backpage').offset==99
# Cover file-shard boundaries in the production reader, not only ASCII UI labels.
alpha=lua.execute((ROOT/'app/scripts/font.lua').read_text())
for name in ['body-28','detail-22','title-34']:
    data=b''.join(p.read_bytes() for p in sorted((ROOT/'app/assets').glob(name+'-*.afn')))
    _,w,h,count,_=struct.unpack('<4sHHII',data[:16]);base=16+count*12
    crossings=[]
    for i in range(count):
        cp,offset,length,_=struct.unpack_from('<IIHH',data,16+i*12)
        if (base+offset)//262144 != (base+offset+length-1)//262144:crossings.append(cp)
    assert crossings
    f=alpha.open(str(ROOT/f'app/assets/{name}.afn'))
    for cp in crossings:alpha.paint(screen,f,0,0,cp,0xff202124,0xffffffff)
    alpha.close(f)
render.close();print('Pinyin Chinese input, UTF-8 deletion, event protocol, output controls, pagination and eight screen layouts passed')

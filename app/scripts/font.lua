-- Private AFN1 alpha atlases: seek only the glyph required by this frame.
-- Tile cache is bounded; CJK coverage does not require multi-megabyte RAM loads.
local F={}
local CHUNK=256*1024
function F.open(path)
 local stem=path:sub(1,-5);local file=assert(io.open(stem..'-000.afn','rb'));local magic,w,h,count,fallback=string.unpack('<c4I2I2I4I4',assert(file:read(16)))
 assert(magic=='AFN1'and count<30000 and w<=48 and h<=48,'Invalid alpha font')
 local index=assert(file:read(count*12));assert(#index==count*12 and 16+#index<=CHUNK,'Invalid alpha font index');file:close()
 return{stem=stem,w=w,h=h,count=count,fallback=fallback,index=index,base=16+count*12,cache={},used=0}
end
local function record(f,cp)
 local low,high=0,f.count-1
 while low<=high do
  local mid=(low+high)//2;local code,offset,len,advance=string.unpack('<I4I4I2I2',f.index,mid*12+1)
  if code==cp then return offset,len,advance elseif code<cp then low=mid+1 else high=mid-1 end
 end
 if cp~=f.fallback then return record(f,f.fallback)end
 return 0,0,f.w
end
function F.advance(f,cp)local _,_,advance=record(f,cp);return advance end
local palettes={}
local function palette(fg,bg)
 local key=tostring(fg)..':'..tostring(bg);if palettes[key]then return palettes[key]end
 local p={};for alpha=0,15 do
  local r=(((fg>>16)&255)*alpha+((bg>>16)&255)*(15-alpha)+7)//15
  local g=(((fg>>8)&255)*alpha+((bg>>8)&255)*(15-alpha)+7)//15
  local b=((fg&255)*alpha+(bg&255)*(15-alpha)+7)//15
  p[alpha]=string.pack('<I2',((r>>3)<<11)|((g>>2)<<5)|(b>>3))
 end
 palettes[key]=p;return p
end
local function read(f,offset,len)
 local out={}
 while len>0 do
  local part=offset//CHUNK
  if f.part~=part then
   if f.file then f.file:close();f.file=nil end
   f.file=assert(io.open(f.stem..string.format('-%03d.afn',part),'rb'));f.part=part
  end
  local position=offset%CHUNK;local size=math.min(len,CHUNK-position)
  assert(f.file:seek('set',position));local bytes=assert(f.file:read(size));assert(#bytes==size,'Short alpha font shard')
  out[#out+1]=bytes;offset=offset+size;len=len-size
 end
 return table.concat(out)
end
function F.paint(sc,f,x,y,cp,fg,bg)
 local key=cp..':'..fg..':'..bg;local tile=f.cache[key]
 if not tile then
  local offset,len=record(f,cp);if len==0 then return end
  local raw=read(f,f.base+offset,len)
  local p=palette(fg,bg);local chunks={}
  for i=1,#raw do local byte=raw:byte(i);chunks[i]=p[byte>>4]:rep((byte&15)+1)end
  tile=table.concat(chunks);assert(#tile==f.w*f.h*2,'Invalid alpha glyph run')
  if f.used>=256 then f.cache={};f.used=0 end
  f.cache[key]=tile;f.used=f.used+1
 end
 sc:blit(math.floor(x),math.floor(y),tile,{width=f.w,height=f.h,format='rgb565'})
end
function F.close(f)if f and f.file then f.file:close();f.file=nil end end
return F

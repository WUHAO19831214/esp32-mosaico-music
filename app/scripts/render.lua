local R={}
local C={bg=0xFFF5F4EF,card=0xFFFFFFFF,text=0xFF17241D,dim=0xFF647269,line=0xFFE1E5DC,accent=0xFF245D47,soft=0xFFE3ECE2,red=0xFFAC493D}
function R.init(display,root)
 R.fonts={};for i=0,6 do R.fonts[i]=display.load_font(root..'/assets/cjk-'..i..'.dfn')end
 R.title=display.load_font(root..'/assets/title-34.dfn');R.model=dofile(root..'/scripts/model.lua');R.model.dictionary=dofile(root..'/scripts/pinyin_dict.lua')
end
function R.close()for _,f in pairs(R.fonts or{})do pcall(f.close,f)end;if R.title then pcall(R.title.close,R.title)end end
local function font(cp,title)return title and R.title or R.fonts[cp>=0x4e00 and cp<0xa000 and 1+(cp-0x4e00)//3500 or 0]end
local function width(sc,value,title)local w=0;for _,cp in utf8.codes(tostring(value or''))do local a=sc:measure_text(utf8.char(cp),{font=font(cp,title)});w=w+a end;return w end
local function text(sc,x,y,value,color,maxwidth,title)
 x=math.floor(x);y=math.floor(y);local s=tostring(value or'');local total=width(sc,s,title);local right=x+(maxwidth or 440);local ell=width(sc,'…',title)
 for _,cp in utf8.codes(s)do local c=utf8.char(cp);local f=font(cp,title);local advance=sc:measure_text(c,{font=f});if x+advance+(total>(maxwidth or 440)and ell or 0)>right then sc:text(x,y,'…',{font=font(0x2026,title),color=color or C.text});break end;sc:text(x,y,c,{font=f,color=color or C.text});x=x+advance end
end
local function wrap(sc,x,y,s,maxwidth,lines,color)
 local row,line=0,''
 for _,cp in utf8.codes(tostring(s or''))do local ch=utf8.char(cp);if width(sc,line..ch)>maxwidth and line~=''then text(sc,x,y+row*37,line,color,maxwidth);row=row+1;line='';if row>=lines then return end end;line=line..ch end
 if line~=''then text(sc,x,y+row*37,line,color,maxwidth)end
end
local function button(sc,x,y,w,h,label,active)
 sc:fill_round_rect(x,y,w,h,12,active and C.accent or C.soft)
 local limit=(utf8.len(label)==1)and(w-4)or(w-14)
 local tw=math.min(limit,width(sc,label));text(sc,x+math.max(2,(w-tw)//2),y+(h-34)//2,label,active and C.card or C.text,limit)
end
local function clock(v)v=math.floor(v or 0);return string.format('%d:%02d',v//60,v%60)end
local names={now='正在播放',songs='歌曲',search='搜歌',account='网易云',settings='设置',lists='我的歌单',bluetooth='蓝牙音箱',outputs='音频输出'}
local function output(s)return s.data.audio and s.data.audio.selected or{name='等待确认输出'}end
function R.draw(sc,s,now)
 local d=s.data;local M=R.model;local a=d.audio or{};local selected=output(s)
 sc:begin({clear=C.bg});text(sc,18,12,names[s.page]or'音乐',C.text,275,true)
 sc:fill_circle(424,29,4,M.linked(s,now)and C.accent or C.red);text(sc,447,13,'X',C.dim,28)
 if s.page=='search'then button(sc,302,8,120,45,'语音',true)
 elseif s.page=='settings'then button(sc,302,8,120,45,'试听',false)
 elseif s.page=='bluetooth'then button(sc,302,8,120,45,a.busy and'扫描中'or'扫描',true)end
 if s.page=='now'then
  text(sc,20,66,(d.target=='bluetooth'and'蓝牙 · 'or'输出 · ')..(selected.name or'未选择'),selected.available==false and C.red or C.accent,440)
  wrap(sc,20,111,d.current and d.current.name or'选一首喜欢的歌',440,2,C.text)
  text(sc,20,192,d.current and d.current.artist or'从歌单或搜歌开始',C.dim,440)
  wrap(sc,20,249,(d.error or'')~=''and d.error or(d.lyric or'')~=''and d.lyric or'让音乐留在桌面',440,2,(d.error or'')~=''and C.red or C.accent)
  sc:fill_round_rect(20,323,440,5,2,C.line);local duration=d.current and d.current.duration or 0
  if duration>0 then sc:fill_round_rect(20,323,math.max(5,math.floor(440*math.min(1,(d.position or 0)/duration))),5,2,C.accent)end
  text(sc,20,334,clock(d.position)..' / '..clock(duration)..(d.target=='esp32'and'  约'or''),C.dim,440)
  button(sc,16,374,136,46,'上一首');button(sc,172,374,136,46,d.status=='playing'and'暂停'or'播放',true);button(sc,328,374,136,46,'下一首')
 elseif s.page=='songs'or s.page=='lists'then
  local list=s.page=='lists'and(d.lists or{})or(d.results or{});local total=s.page=='lists'and(d.list_total or #list)or(d.result_total or #list);local off=s.page=='lists'and(d.list_offset or s.offset)or(d.result_offset or s.offset);local page_size=d.page_size or 3
  button(sc,16,70,124,44,'上页');text(sc,174,76,tostring(math.floor(off/page_size+1))..' / '..math.max(1,math.ceil(total/page_size)),C.dim,140);button(sc,340,70,124,44,'下页')
  if #list==0 then wrap(sc,24,190,s.await_result and'正在查找，请稍候…'or s.page=='lists'and'请先登录，再打开我的歌单'or'还没有歌曲，去搜一首吧',432,3,C.dim)end
  for row=1,3 do local item=list[row+s.offset];if item then local y=128+(row-1)*95;sc:fill_round_rect(16,y,448,88,14,C.card);text(sc,29,y+9,item.name,C.text,420);text(sc,29,y+48,item.artist or'打开歌单',C.dim,420)end end
 elseif s.page=='search'then
  sc:fill_round_rect(16,65,448,49,12,C.card);text(sc,28,73,s.query~=''and s.query or'输入歌名或歌手',s.query~=''and C.text or C.dim,422)
  text(sc,20,122,s.composition~=''and s.composition or(s.ime and'拼音选字'or'英文输入'),C.accent,278);button(sc,314,120,72,36,s.ime and'中'or'EN');button(sc,394,120,70,36,'删')
  local candidates=M.candidates(s)
  if #candidates>0 then for i=1,3 do local c=candidates[i+s.candidate_offset];if c then button(sc,16+(i-1)*128,164,120,42,c)end end;button(sc,408,164,56,42,'>')
  else text(sc,20,169,(d.voice and not({idle=true,done=true})[d.voice.state])and d.voice.message or'输入拼音后点选汉字',C.dim,440)end
  for row,letters in ipairs(M.keys)do local left=({14,36,82})[row];for col=1,#letters do button(sc,left+(col-1)*45,216+(row-1)*50,42,44,letters:sub(col,col))end end
  button(sc,16,370,104,48,'清空');button(sc,132,370,140,48,s.composition~=''and'上字'or'空格');button(sc,284,370,180,48,'搜歌',true)
  if d.voice and({permission=true,recording=true,recognizing=true})[d.voice.state]then sc:fill_round_rect(16,162,448,200,16,C.card);sc:fill_circle(240,220,24,C.soft);wrap(sc,32,270,d.voice.message or'正在处理语音…',416,2,C.accent)end
 elseif s.page=='account'then
  text(sc,20,73,(d.profile or'')~=''and d.profile or'使用网易云 App 扫码',C.accent,440)
  if(d.profile or'')~=''then
   sc:fill_circle(240,208,52,C.soft);sc:line(212,208,232,229,C.accent);sc:line(232,229,270,185,C.accent);text(sc,169,282,'登录成功',C.text,260)
  elseif s.qr and s.qr.bits then local n=math.floor(s.qr.size);local unit=math.min(5,math.floor(218/(n+8)));local size=(n+8)*unit;local left=(480-size)//2;local top=115;sc:fill_rect(left,top,size,size,C.card);for y=0,n-1 do for x=0,n-1 do if s.qr.bits:sub(y*n+x+1,y*n+x+1)=='1'then sc:fill_rect(left+(x+4)*unit,top+(y+4)*unit,unit,unit,C.text)end end end;text(sc,20,326,s.qr.message or'等待扫码',C.dim,440)
  else wrap(sc,24,178,'登录后，可以在这里找到自己的歌单。',432,3,C.dim)end
  button(sc,16,364,216,52,'扫码登录');button(sc,248,364,216,52,'我的歌单',true)
 elseif s.page=='settings'then
  sc:fill_round_rect(16,70,448,82,14,C.card);text(sc,28,76,selected.name or'尚未选择输出',C.text,422);text(sc,28,113,selected.available and'输出已确认'or'设备离线，请重新选择',selected.available and C.accent or C.red,422)
  button(sc,16,166,216,48,'机身扬声器',d.target=='esp32');button(sc,248,166,216,48,'Mac 扬声器',d.target=='mac')
  button(sc,16,224,448,48,'蓝牙音箱  选择 >',d.target=='bluetooth');button(sc,16,282,448,44,'更多音频输出 >')
  text(sc,20,352,'音量 '..math.floor(d.volume or 30)..'%',C.text,225);button(sc,246,340,98,64,'-');button(sc,356,340,108,64,'+')
 elseif s.page=='bluetooth'or s.page=='outputs'then
  text(sc,20,65,s.page=='bluetooth'and(a.message or'请让音箱进入配对模式')or(a.host or'当前 Mac'),C.dim,440)
  local list=s.page=='bluetooth'and(a.devices or{})or(a.outputs or{});button(sc,16,108,124,42,'上页');text(sc,183,112,tostring(s.bt_offset//3+1),C.dim,140);button(sc,340,108,124,42,'下页')
  if #list==0 then wrap(sc,24,208,s.page=='bluetooth'and'还没有音箱。点击扫描，或在 Mac 蓝牙设置中配对。'or'正在读取本机音频输出…',430,4,C.dim)end
  for row=1,3 do local item=list[row+s.bt_offset];if item then local y=160+(row-1)*84;local active=s.page=='bluetooth'and d.target=='bluetooth'and selected.address==item.address and selected.available or s.page=='outputs'and d.target=='mac'and selected.uid==item.uid;sc:fill_round_rect(16,y,448,78,12,active and C.soft or C.card);text(sc,28,y+4,item.name,C.text,305);text(sc,28,y+41,active and'已选 · 已确认'or item.connected and'已连接'or item.paired and'已配对'or'可配对',active and C.accent or C.dim,305);button(sc,346,y+15,104,48,active and'已选'or s.page=='bluetooth'and'连接'or'选择',active)end end
 end
 local active=s.page;if active=='lists'then active='account'elseif active=='bluetooth'or active=='outputs'then active='settings'end
 sc:fill_rect(0,426,480,54,C.card);sc:fill_rect(0,426,480,1,C.line)
 for i,p in ipairs({'now','songs','search','account','settings'})do if active==p then sc:fill_round_rect((i-1)*96+6,435,84,37,10,C.soft)end;text(sc,(i-1)*96+19,439,({'播放','歌曲','搜歌','账号','设置'})[i],active==p and C.accent or C.dim,70)end
 sc:present()
end
return R

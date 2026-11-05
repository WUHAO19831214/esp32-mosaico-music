local R={}
local C={bg=0xFFF6F6F6,card=0xFFFFFFFF,text=0xFF202124,dim=0xFF747880,line=0xFFE5E5E5,
 accent=0xFFEC4141,soft=0xFFFCE9E9,neutral=0xFFEEEEEE,shadow=0xFFE5E5E5,red=0xFFD63737}
local F
local icons={speaker=0xe000,bluetooth=0xe001,mic=0xe002,check=0xe003,search=0xe004,
 chevron=0xe005,close=0xe006,play=0xe007,pause=0xe008,prev=0xe009,next=0xe00a,
 songs=0xe00b,account=0xe00c,settings=0xe00d,minus=0xe00e,plus=0xe00f,monitor=0xe010}
function R.init(display,root)
 F=dofile(root..'/scripts/font.lua');R.fonts={}
 for _,entry in ipairs({{'body','body-28'},{'detail','detail-22'},{'title','title-34'},{'icons','icons'}})do
  R.fonts[entry[1]]=F.open(root..'/assets/'..entry[2]..'.afn')
 end
 R.model=dofile(root..'/scripts/model.lua');R.model.dictionary=dofile(root..'/scripts/pinyin_dict.lua')
end
function R.close()for _,f in pairs(R.fonts or{})do pcall(F.close,f)end end
local function font(style)return R.fonts[style or'body']end
local function width(value,style)
 local w=0;for _,cp in utf8.codes(tostring(value or''))do w=w+F.advance(font(style),cp)end;return w
end
local function text(sc,x,y,value,color,maxwidth,style,bg)
 x=math.floor(x);y=math.floor(y);local s=tostring(value or'');local f=font(style)
 local limit=maxwidth or 440;local total=width(s,style);local right=x+limit;local ell=F.advance(f,0x2026)
 for _,cp in utf8.codes(s)do
  local advance=F.advance(f,cp)
  if x+advance+(total>limit and ell or 0)>right then F.paint(sc,f,x,y,0x2026,color or C.text,bg or C.bg);break end
  F.paint(sc,f,x,y,cp,color or C.text,bg or C.bg);x=x+advance
 end
end
local function icon(sc,x,y,name,color,bg)F.paint(sc,R.fonts.icons,x,y,assert(icons[name],name),color or C.dim,bg or C.bg)end
local function wrap(sc,x,y,value,maxwidth,lines,color,style,bg)
 local row,line=0,'';local step=style=='title'and 43 or 37
 for _,cp in utf8.codes(tostring(value or''))do
  local ch=utf8.char(cp)
  if width(line..ch,style)>maxwidth and line~=''then
   if row==lines-1 then text(sc,x,y+row*step,line..ch..'…',color,maxwidth,style,bg);return end
   text(sc,x,y+row*step,line,color,maxwidth,style,bg);row=row+1;line=''
  end
  line=line..ch
 end
 if line~=''then text(sc,x,y+row*step,line,color,maxwidth,style,bg)end
end
local function card(sc,x,y,w,h,bg)
 sc:fill_round_rect(x,y+2,w,h,15,C.shadow);sc:fill_round_rect(x,y,w,h,15,bg or C.card)
end
local function button(sc,x,y,w,h,label,active,symbol,detail)
 local pressed=R.pressed and R.model.hit(R.state,x+w//2,y+h//2)==R.pressed
 local bg=active and(pressed and C.red or C.accent)or(pressed and C.soft or C.neutral);local fg=active and C.card or C.text
 sc:fill_round_rect(x,y+1,w,h,12,C.shadow);sc:fill_round_rect(x,y,w,h,12,bg)
 local style=detail and'detail'or'body';local limit=w-(symbol and 44 or utf8.len(label)==1 and 4 or 16)
 local tw=math.min(limit,width(label,style));local left=x+math.max(2,(w-tw-(symbol and 36 or 0))//2)
 if symbol then icon(sc,left,y+(h-28)//2,symbol,fg,bg);left=left+36 end
 text(sc,left,y+(h-(detail and 30 or 36))//2,label,fg,limit,style,bg)
end
local function rowbutton(sc,x,y,w,h,label,symbol,active)
 local pressed=R.pressed and R.model.hit(R.state,x+w//2,y+h//2)==R.pressed
 local bg=active and(pressed and C.red or C.accent)or(pressed and C.soft or C.neutral);local fg=active and C.card or C.text
 sc:fill_round_rect(x,y,w,h,12,bg);icon(sc,x+16,y+(h-28)//2,symbol,fg,bg)
 text(sc,x+58,y+(h-36)//2,label,fg,w-108,nil,bg);icon(sc,x+w-40,y+(h-28)//2,'chevron',fg,bg)
end
local function clock(v)v=math.floor(v or 0);return string.format('%d:%02d',v//60,v%60)end
local names={now='正在播放',songs='歌曲',search='搜歌',account='网易云',settings='设置',lists='我的歌单',bluetooth='蓝牙音箱',outputs='音频输出'}
local function output(s)return s.data.audio and s.data.audio.selected or{name='等待确认输出'}end
function R.draw(sc,s,now)
 local d=s.data;local M=R.model;local a=d.audio or{};local selected=output(s);R.state=s;R.pressed=s.pressed_hit
 sc:begin({clear=C.bg});text(sc,20,10,names[s.page]or'音乐',C.text,275,'title')
 sc:fill_circle(430,29,3,M.linked(s,now)and C.accent or C.dim);icon(sc,446,16,'close',C.dim)
 if s.page=='search'then button(sc,302,8,120,45,'语音',true,'mic')
 elseif s.page=='settings'then button(sc,302,8,120,45,'试听',false,'speaker')
 elseif s.page=='bluetooth'then button(sc,302,8,120,45,a.busy and'扫描中'or'扫描',true,nil,a.busy)end
 if s.page=='now'then
  sc:fill_round_rect(16,65,448,39,12,C.card)
  icon(sc,26,71,d.target=='bluetooth'and'bluetooth'or'speaker',selected.available==false and C.red or C.accent,C.card)
  text(sc,64,69,selected.name or'未选择输出',selected.available==false and C.red or C.dim,352,'detail',C.card)
  icon(sc,428,71,'chevron',C.dim,C.card)
  wrap(sc,20,119,d.current and d.current.name or'选一首喜欢的歌',440,2,C.text,'title')
  text(sc,20,205,d.current and d.current.artist or'从歌单或搜歌开始',C.dim,440,'detail')
  wrap(sc,20,253,(d.error or'')~=''and d.error or(d.lyric or'')~=''and d.lyric or'让音乐留在桌面',440,2,(d.error or'')~=''and C.red or C.accent)
  sc:fill_round_rect(20,332,440,5,2,C.line);local duration=d.current and d.current.duration or 0
  if duration>0 then sc:fill_round_rect(20,332,math.max(5,math.floor(440*math.min(1,(d.position or 0)/duration))),5,2,C.accent)end
  text(sc,20,340,clock(d.position),C.dim,170,'detail');local endtime=clock(duration)..(d.target=='esp32'and'  约'or'')
  text(sc,460-width(endtime,'detail'),340,endtime,C.dim,170,'detail')
  button(sc,16,374,136,46,'上一首');button(sc,172,374,136,46,d.status=='playing'and'暂停'or'播放',true,d.status=='playing'and'pause'or'play');button(sc,328,374,136,46,'下一首')
 elseif s.page=='songs'or s.page=='lists'then
  local list=s.page=='lists'and(d.lists or{})or(d.results or{});local total=s.page=='lists'and(d.list_total or #list)or(d.result_total or #list)
  local off=s.page=='lists'and(d.list_offset or s.offset)or(d.result_offset or s.offset);local page_size=d.page_size or 3
  button(sc,16,70,124,44,'上页',false,nil,true)
  local pagination=tostring(math.floor(off/page_size+1))..' / '..math.max(1,math.ceil(total/page_size))
  text(sc,(480-width(pagination,'detail'))//2,77,pagination,C.dim,160,'detail');button(sc,340,70,124,44,'下页',false,nil,true)
  if #list==0 then icon(sc,226,169,'search',C.dim);wrap(sc,24,225,s.await_result and'正在查找，请稍候…'or s.page=='lists'and'请先登录，再打开我的歌单'or'还没有歌曲，去搜一首吧',432,3,C.dim)end
  for row=1,3 do
   local item=list[row+s.offset]
   if item then local y=128+(row-1)*95;local active=d.current and tostring(item.id)==tostring(d.current.id)and s.page=='songs';local bg=(active or R.pressed==(s.page=='lists'and'list:'or'song:')..(row+s.offset))and C.soft or C.card
    card(sc,16,y,448,88,bg);text(sc,30,y+9,item.name,active and C.accent or C.text,378,nil,bg)
    text(sc,30,y+49,item.artist or'打开歌单',C.dim,378,'detail',bg);icon(sc,422,y+30,s.page=='lists'and'chevron'or active and d.status=='playing'and'pause'or'play',active and C.accent or C.dim,bg)
   end
  end
 elseif s.page=='search'then
  card(sc,16,65,448,49);icon(sc,28,75,'search',C.dim,C.card)
  text(sc,66,72,s.query~=''and s.query or'输入歌名或歌手',s.query~=''and C.text or C.dim,384,nil,C.card)
  text(sc,20,121,s.composition~=''and s.composition or(s.ime and'拼音选字'or'英文输入'),C.accent,278)
  button(sc,314,120,72,36,s.ime and'中'or'EN',false,nil,true);button(sc,394,120,70,36,'删',false,nil,true)
  local candidates=M.candidates(s)
  if #candidates>0 then
   for i=1,3 do local c=candidates[i+s.candidate_offset];if c then button(sc,16+(i-1)*128,164,120,42,c)end end
   sc:fill_round_rect(408,164,56,42,12,C.neutral);icon(sc,422,171,'chevron',C.text,C.neutral)
  else text(sc,20,170,(d.voice and not({idle=true,done=true})[d.voice.state])and d.voice.message or'输入拼音，点选上方候选字',C.dim,440,'detail')end
  for row,letters in ipairs(M.keys)do local left=({14,36,82})[row];for col=1,#letters do button(sc,left+(col-1)*45,216+(row-1)*50,42,44,letters:sub(col,col))end end
  button(sc,16,370,104,48,'清空');button(sc,132,370,140,48,s.composition~=''and'上字'or'空格');button(sc,284,370,180,48,'搜歌',true,'search')
  if d.voice and({permission=true,recording=true,recognizing=true})[d.voice.state]then
   card(sc,16,162,448,200);sc:fill_circle(240,219,35,C.soft);icon(sc,226,205,'mic',C.accent,C.soft)
   wrap(sc,36,274,d.voice.message or'正在处理语音…',408,2,C.accent,nil,C.card)
  end
 elseif s.page=='account'then
  text(sc,20,73,(d.profile or'')~=''and d.profile or'使用网易云 App 扫码',C.dim,440)
  if(d.profile or'')~=''then
   sc:fill_circle(240,207,48,C.soft);icon(sc,226,193,'check',C.accent,C.soft)
   local label='登录成功';text(sc,(480-width(label))//2,279,label,C.text,260)
  elseif s.qr and s.qr.bits then
   local n=math.floor(s.qr.size);local unit=math.min(5,math.floor(218/(n+8)));local size=(n+8)*unit;local left=(480-size)//2;local top=115
   sc:fill_rect(left,top,size,size,C.card)
   for y=0,n-1 do for x=0,n-1 do if s.qr.bits:sub(y*n+x+1,y*n+x+1)=='1'then sc:fill_rect(left+(x+4)*unit,top+(y+4)*unit,unit,unit,C.text)end end end
   text(sc,20,327,s.qr.message or'等待扫码',C.dim,440,'detail')
  else icon(sc,226,163,'account',C.accent);wrap(sc,24,222,'登录后，可以在这里找到自己的歌单。',432,3,C.dim)end
  button(sc,16,364,216,52,'扫码登录');button(sc,248,364,216,52,'我的歌单',true)
 elseif s.page=='settings'then
  card(sc,16,70,448,82);text(sc,28,77,selected.name or'尚未选择输出',C.text,420,nil,C.card)
  icon(sc,28,118,selected.available and'check'or'speaker',selected.available and C.accent or C.red,C.card)
  text(sc,64,115,selected.available and'输出已确认'or'设备离线，请重新选择',selected.available and C.accent or C.red,380,'detail',C.card)
  button(sc,16,166,216,48,'机身扬声器',d.target=='esp32','speaker');button(sc,248,166,216,48,'Mac 扬声器',d.target=='mac','monitor')
  rowbutton(sc,16,224,448,48,'蓝牙音箱','bluetooth',d.target=='bluetooth')
  rowbutton(sc,16,282,448,44,'更多音频输出','speaker')
  icon(sc,24,357,'speaker',C.text);text(sc,62,352,'音量 '..math.floor(d.volume or 30)..'%',C.text,180)
  for _,b in ipairs({{246,98,'minus'},{356,108,'plus'}})do sc:fill_round_rect(b[1],341,b[2],64,14,C.shadow);sc:fill_round_rect(b[1],340,b[2],64,14,C.neutral);icon(sc,b[1]+(b[2]-28)//2,358,b[3],C.text,C.neutral)end
 elseif s.page=='bluetooth'or s.page=='outputs'then
  text(sc,20,66,s.page=='bluetooth'and(a.message or'请让音箱进入配对模式')or(a.host or'当前 Mac'),C.dim,440,'detail')
  local list=s.page=='bluetooth'and(a.devices or{})or(a.outputs or{});button(sc,16,108,124,42,'上页',false,nil,true)
  local pagination=tostring(s.bt_offset//3+1)..' / '..math.max(1,math.ceil(#list/3));text(sc,(480-width(pagination,'detail'))//2,113,pagination,C.dim,160,'detail');button(sc,340,108,124,42,'下页',false,nil,true)
  if #list==0 then icon(sc,226,193,s.page=='bluetooth'and'bluetooth'or'speaker',C.accent);wrap(sc,24,247,s.page=='bluetooth'and'还没有音箱。点击扫描，或在 Mac 蓝牙设置中配对。'or'正在读取本机音频输出…',430,4,C.dim)end
  for row=1,3 do
   local item=list[row+s.bt_offset]
   if item then local y=160+(row-1)*84;local active=s.page=='bluetooth'and d.target=='bluetooth'and selected.address==item.address and selected.available or s.page=='outputs'and d.target=='mac'and selected.uid==item.uid
    local bg=active and C.soft or C.card;card(sc,16,y,448,78,bg);text(sc,28,y+5,item.name,C.text,298,nil,bg)
    text(sc,28,y+43,active and'已选 · 已确认'or item.connected and'已连接'or item.paired and'已配对'or'可配对',active and C.accent or C.dim,298,'detail',bg)
    button(sc,346,y+15,104,48,active and'已选'or s.page=='bluetooth'and'连接'or'选择',active)
   end
  end
 end
 local active=s.page;if active=='lists'then active='account'elseif active=='bluetooth'or active=='outputs'then active='settings'end
 sc:fill_rect(0,426,480,54,C.card);sc:fill_rect(0,426,480,1,C.line)
 for i,p in ipairs({'now','songs','search','account','settings'})do
  local x=(i-1)*96;local bg=active==p and C.soft or C.card;local fg=active==p and C.accent or C.dim
  if active==p then sc:fill_round_rect(x+5,435,86,37,11,bg)end
  icon(sc,x+10,439,({'play','songs','search','account','settings'})[i],fg,bg)
  text(sc,x+42,439,({'播放','歌曲','搜歌','账号','设置'})[i],fg,49,'detail',bg)
 end
 sc:present()
end
return R

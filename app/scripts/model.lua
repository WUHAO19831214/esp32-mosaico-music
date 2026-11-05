local M={page_size=3,keys={'QWERTYUIOP','ASDFGHJKL','ZXCVBNM'}}
local phrases={zhoujielun='周杰伦',linjunjie='林俊杰',chenyixun='陈奕迅',wangfei='王菲',denglijun='邓丽君',maobuyi='毛不易',xuezhiqian='薛之谦',liyonghao='李荣浩',lieronghao='李荣浩',mozate='莫扎特',chuanqi='传奇',qingtian='晴天',daoxiang='稻香',yueguang='月光',haidi='海底',xiaoxingxing='小星星'}
function M.new()return{page='now',offset=0,bt_offset=0,query='',composition='',ime=true,candidate_offset=0,seen=-100000,data={target='esp32',status='idle',volume=30,results={},lists={},profile='',error='',lyric='',audio={devices={},outputs={},selected={name='等待连接'}}}}end
function M.feed(s,d,now)
 if s.await_result and(d.result_seq or 0)<=s.await_result then d.results={}else s.await_result=nil end
 s.data=d;s.seen=now;if d.result_total then s.offset=0 end
 if d.voice and d.voice.seq~=s.voice_seq then
  s.voice_seq=d.voice.seq
  if d.voice.state=='done'and(d.voice.text or'')~=''then s.query=d.voice.text;s.composition='';if s.page=='search'then s.page='songs'end end
 end
end
function M.linked(s,now)return now-s.seen<10000 end
function M.truncate(v,n)v=tostring(v or'');if(utf8.len(v)or 0)<=n then return v end;return v:sub(1,(utf8.offset(v,n)or #v)-1)..'…'end
function M.candidates(s)
 local list={};if s.composition==''then return list end
 if phrases[s.composition]then list[#list+1]=phrases[s.composition]end
 local value=M.dictionary and M.dictionary[s.composition]or''
 for _,cp in utf8.codes(value)do list[#list+1]=utf8.char(cp)end
 return list
end
local function back(v)local i=utf8.offset(v,-1);return i and v:sub(1,i-1)or''end
local function commit(s,value)s.query=s.query..value;s.composition='';s.candidate_offset=0 end
function M.hit(s,x,y)
 x=math.floor(x);y=math.floor(y)
 if x>=436 and y<58 then return'exit'end
 if y>=426 then return({'now','songs','search','account','settings'})[math.min(5,x//96+1)]end
 if s.page=='now'then
  if y>=64 and y<101 then return'settings'end
  if y>=370 and y<422 then return x<164 and'prev'or x<316 and'toggle'or'next'end
 elseif s.page=='songs'or s.page=='lists'then
  if y>=68 and y<116 then return x<145 and'backpage'or x>335 and'nextpage'or nil end
  if y>=128 and y<413 then local i=(y-128)//95+1+s.offset;local list=s.page=='lists'and(s.data.lists or{})or(s.data.results or{});if list[i]then return(s.page=='lists'and'list:'or'song:')..i end end
 elseif s.page=='search'then
  if s.data.voice and({permission=true,recording=true,recognizing=true})[s.data.voice.state]then return nil end
  if x>=300 and x<432 and y<58 then return'voice'end
  if y>=118 and y<156 then if x>=394 then return'backspace'elseif x>=312 then return'mode'end end
  if y>=162 and y<208 then if x>=408 then return'candidate_next'end;local i=(x-16)//128+1+s.candidate_offset;if i>=1 and M.candidates(s)[i]then return'candidate:'..i end end
  for row=1,3 do local top=216+(row-1)*50;local left=({14,36,82})[row];if y>=top and y<top+44 and x>=left then local col=(x-left)//45+1;if col<=#M.keys[row]then return'letter:'..M.keys[row]:sub(col,col)end end end
  if y>=370 and y<421 then return x<126 and'clear'or x<280 and'space'or'submit'end
 elseif s.page=='account'then
  if y>=364 and y<418 then return x<240 and'login'or'playlists'end
 elseif s.page=='settings'then
  if x>=300 and x<432 and y<58 then return'audio-test'end
  if y>=166 and y<214 then return x<240 and'output_esp32'or'output_mac'end
  if y>=224 and y<273 then return'bluetooth'end
  if y>=282 and y<327 then return'outputs'end
  if y>=339 and y<403 then return x>=356 and'vol_up'or x>=246 and'vol_down'or nil end
 elseif s.page=='bluetooth'or s.page=='outputs'then
  if s.page=='bluetooth'and x>=300 and x<432 and y<58 then return'bt-scan'end
  if y>=107 and y<151 then return x<145 and'localprev'or x>335 and'localnext'or nil end
  if y>=160 and y<412 then local i=(y-160)//84+1+s.bt_offset;local a=s.data.audio or{};local list=s.page=='bluetooth'and(a.devices or{})or(a.outputs or{});if list[i]then return(s.page=='bluetooth'and'bt:'or'output:')..i end end
 end
end
function M.action(s,hit)
 if not hit then return end
 if hit=='exit'then return{exit=true}end
 if hit=='now'or hit=='songs'or hit=='search'or hit=='account'or hit=='settings'then s.page=hit;s.offset=0;return end
 if hit=='bluetooth'or hit=='outputs'then s.page=hit;s.bt_offset=0;return{action='audio-refresh'}end
 if hit=='localnext'or hit=='localprev'then local a=s.data.audio or{};local list=s.page=='bluetooth'and(a.devices or{})or(a.outputs or{});s.bt_offset=math.max(0,math.min(math.max(0,(#list-1)//3*3),s.bt_offset+(hit=='localnext'and 3 or-3)));return end
 if hit=='nextpage'or hit=='backpage'then
  local total=s.page=='lists'and s.data.list_total or s.data.result_total;local count=math.floor(s.data.page_size or M.page_size)
  if total then local offset=s.page=='lists'and(s.data.list_offset or 0)or(s.data.result_offset or 0);return{action='devicepage',kind=s.page,offset=math.max(0,math.min(math.max(0,(math.floor(total)-1)//count*count),math.floor(offset)+(hit=='nextpage'and count or-count)))}end
  local list=s.page=='lists'and(s.data.lists or{})or(s.data.results or{});s.offset=math.max(0,math.min(math.max(0,(#list-1)//count*count),s.offset+(hit=='nextpage'and count or-count)));return
 end
 if hit:sub(1,7)=='letter:'then local c=hit:sub(8):lower();if #s.query+#s.composition>=120 then return end;if s.ime then s.composition=s.composition..c;s.candidate_offset=0 else s.query=s.query..c end;return end
 if hit:sub(1,10)=='candidate:'then local c=M.candidates(s)[tonumber(hit:sub(11))];if c then commit(s,c)end;return end
 if hit=='candidate_next'then local n=#M.candidates(s);s.candidate_offset=s.candidate_offset+3;if s.candidate_offset>=n then s.candidate_offset=0 end;return end
 if hit=='mode'then if s.composition~=''then commit(s,s.composition)end;s.ime=not s.ime;return end
 if hit=='backspace'then if s.composition~=''then s.composition=back(s.composition);s.candidate_offset=0 else s.query=back(s.query)end;return end
 if hit=='clear'then s.query='';s.composition='';s.candidate_offset=0;return end
 if hit=='space'then if s.composition~=''then commit(s,M.candidates(s)[1]or s.composition)else s.query=s.query..' 'end;return end
 if hit=='submit'then if s.composition~=''then commit(s,M.candidates(s)[1]or s.composition)end;if not s.query:match('%S')then return end;s.await_result=s.data.result_seq or 0;s.page='songs';s.offset=0;s.data.results={};return{action='search',q=s.query}end
 if hit:sub(1,5)=='song:'then local item=s.data.results[tonumber(hit:sub(6))];s.page='now';return{action='select',id=item.id}end
 if hit:sub(1,5)=='list:'then local item=s.data.lists[tonumber(hit:sub(6))];s.page='songs';s.offset=0;s.await_result=s.data.result_seq or 0;s.data.results={};return{action='playlist',id=item.id}end
 if hit:sub(1,3)=='bt:'then local item=s.data.audio.devices[tonumber(hit:sub(4))];return{action='bt-connect',address=item.address}end
 if hit:sub(1,7)=='output:'then local item=s.data.audio.outputs[tonumber(hit:sub(8))];return{action='target',target='mac',uid=item.uid}end
 if hit=='output_esp32'or hit=='output_mac'then return{action='target',target=hit=='output_esp32'and'esp32'or'mac'}end
 if hit=='playlists'then s.page='lists';s.offset=0;return{action='playlists'}end
 if hit=='vol_down'or hit=='vol_up'then return{action='volume',value=math.max(0,math.min(100,(s.data.volume or 30)+(hit=='vol_up'and 10 or-10)))}end
 return{action=hit}
end
function M.event(s,hit,run_id,sequence)local e=M.action(s,hit);if e and not e.exit then e.event_id=tostring(run_id)..'-'..tostring(sequence)end;return e end
return M

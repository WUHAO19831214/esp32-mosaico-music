local display=require('display')
local thread=require('thread')
local storage=require('storage')
local json=require('json')
local delay=require('delay')
local system=require('system')
local root=storage.join_path(storage.get_root_dir(),'apps','music_player')
local M=dofile(root..'/scripts/model.lua')
M.dictionary=dofile(root..'/scripts/pinyin_dict.lua')
local R=dofile(root..'/scripts/render.lua')
local s=M.new();if args and args.page then s.page=args.page end;local sc;local started=system.millis();local frames=0
local function run()
 local found,info=thread.get('music_player_receiver')
 if not found or not info:find('status=running',1,true)then
  local ok,out=thread.start(root..'/scripts/receiver.lua',{}, {name='music_player_receiver',exclusive='music_player_receiver',replace=true,timeout_ms=0});assert(ok,out)
  delay.delay_ms(150)
 end
 for attempt=1,3 do local ok,result=pcall(display.open);if ok then sc=result;break end;if attempt==3 or not tostring(result):find('ESP_ERR_TIMEOUT',1,true)then error(result)end;delay.delay_ms(500)end
 local screen_info=sc:info();assert(screen_info.width==480 and screen_info.height==480)
 sc:begin({clear=0xFFF6F6F6});sc:text(28,215,'Loading music...',{font_size=24,color=0xFFEC4141});sc:present()
 R.init(display,root)
 print('[music] alpha display ready; init_ms='..(system.millis()-started));started=system.millis()
 local pressed,last_draw,dirty,event_num=nil,-1000,true,0
 while true do
  local now=system.millis()
  while true do local raw=thread.sync.queue_recv('music_feed',0);if not raw then break end;M.feed(s,json.decode(raw),now);dirty=true end
  while true do local raw=thread.sync.queue_recv('music_qr',0);if not raw then break end;s.qr=json.decode(raw);dirty=true end
  while true do local raw=thread.sync.queue_recv('music_voice',0);if not raw then break end;s.data.voice=json.decode(raw);dirty=true end
  local p=sc:touch().points[1]
  if p and not pressed then pressed={x=p.x,y=p.y,hit=M.hit(s,p.x,p.y)};s.pressed_hit=pressed.hit;dirty=true
  elseif not p and pressed then
   event_num=event_num+1
   local event=M.event(s,pressed.hit,started,event_num);pressed=nil;s.pressed_hit=nil;dirty=true
   if event and event.exit then break end
   if event then local ok=thread.sync.queue_send('music_events',json.encode(event),0);if not ok then s.data.error='操作过快，请稍后重试'end end
  end
  if now-last_draw>1000 then dirty=true end
  if dirty and now-last_draw>=150 then
   local draw_started=system.millis();R.draw(sc,s,now)
   if frames==0 then print('[music] first frame ready; page='..s.page..'; draw_ms='..(system.millis()-draw_started))elseif frames==1 then print('[music] cached frame; draw_ms='..(system.millis()-draw_started))end
   frames=frames+1;dirty=false;last_draw=now
  end
  if args and args.smoke_ms and now-started>=args.smoke_ms then break end
  delay.delay_ms(25)
 end
end
local ok,err=xpcall(run,debug.traceback)
if sc then pcall(sc.close,sc)end;R.close()
print('[music] UI closed; frames='..frames)
if not ok then error(err)end

local http=require('http_server')
local json=require('json')
local storage=require('storage')
local thread=require('thread')
local system=require('system')
local capability=require('capability')
local root=storage.join_path(storage.get_root_dir(),'apps','music_player')
local cfg=json.decode(assert(storage.read_file(root..'/config.json')))
local instance=tostring(system.time())..'-'..tostring(system.millis())
local audio=dofile(root..'/scripts/audio.lua')
for _,q in ipairs({{'music_feed',4096,2},{'music_qr',4096,2},{'music_events',512,8},{'music_audio_cmd',2048,4},{'music_audio_health',512,2},{'music_voice',1024,2}})do
 local ok,err=thread.sync.queue_create(q[1],{item_size=q[2],depth=q[3]});assert(ok or err=='exists',err)
end
local function latest(name,value)
 local raw=json.encode(value)
 if #raw>4096 then return nil end
 local ok=thread.sync.queue_send(name,raw,0)
 if not ok then thread.sync.queue_recv(name,0);ok=thread.sync.queue_send(name,raw,0) end
 return ok
end
local app=http.app('music_player')
local event,health
local function auth(req)
 local ok,d=pcall(json.decode,req.body)
 if not ok or type(d)~='table' or d.token~=cfg.token then return nil end
 return d
end
app:post('/sync',function(req)
 local d=auth(req);if not d then return {status=403,json={ok=false}} end
 if type(d.data)~='table' or not latest('music_feed',d.data) then return {status=413,json={ok=false,error='快照过大'}} end
 if type(d.qr)=='table' then latest('music_qr',d.qr) end
 if event and d.ack==(event.event_id or event.id)then event=nil end
 if not event then local raw=thread.sync.queue_recv('music_events',0);if raw then event=json.decode(raw) end end
 while true do local raw=thread.sync.queue_recv('music_audio_health',0);if not raw then break end;health=json.decode(raw) end
 return {json={ok=true,event=event,audio=audio.poll()}}
end)
app:post('/audio',function(req)
 local d=auth(req);if not d then return {status=403,json={ok=false}} end
 if not ({play=true,pause=true,resume=true,stop=true,volume=true,tone=true})[d.action] then return {status=400,json={ok=false}} end
 if d.action=='play' and (type(d.url)~='string' or #d.url>1600 or not d.url:match('^https?://'))then return {status=400,json={ok=false,error='无效音频地址'}} end
 local ok,err=audio.command(d)
 return {json={ok=ok==true,error=err}}
end)
app:post('/voice',function(req)
 local d=auth(req);if not d then return {status=403,json={ok=false}}end
 local file=root..'/voice.wav'
 if d.action=='clear'then storage.remove(file);return{json={ok=true}}end
 if d.action~='record'then return{status=400,json={ok=false}}end
 latest('music_voice',{state='recording',message='请说歌名，录音 4 秒',seq=system.millis()})
 local audio_module=require('audio');local input,recorder
 local ok,result=pcall(function()
  input=assert(audio_module.open_input({sample_rate=16000,channels=1,bits=16}))
  recorder=assert(audio_module.recorder({input=input}))
  return assert(recorder:record(file,{duration_ms=4000,sample_rate=16000,channels=1,bits=16}))
 end)
 if recorder then pcall(recorder.close,recorder)end;if input then pcall(input.close,input)end
 latest('music_voice',{state=ok and'recognizing'or'error',message=ok and'正在本机识别…'or tostring(result),seq=system.millis()})
 return{json={ok=ok,result=ok and result or nil,error=not ok and tostring(result)or nil}}
end)
app:post('/ui',function(req)
 local d=auth(req);if not d then return {status=403,json={ok=false}} end
 if d.action=='start' then
  local ok,out=thread.start(root..'/scripts/main.lua',d.args or {},{name='music_player_ui',exclusive='music_player_ui',replace=true,timeout_ms=0})
  return {json={ok=ok==true,result=out}}
 elseif d.action=='stop'then
  local ok,listed=thread.list('running');if not ok then return{status=409,json={ok=false,error=listed}}end
  local stopped={}
  for line in listed:gmatch('[^\n]+')do
   if line:match('path=(.+)$')==root..'/scripts/main.lua'then local id=line:match('^([%w_-]+)');local done,out=thread.stop(id,2000);if not done then return{status=409,json={ok=false,error=out}}end;stopped[#stopped+1]=id end
  end
  return{json={ok=true,stopped=stopped}}
 elseif d.action=='status' then
  local ok,out=thread.get('music_player_ui');return {json={ok=true,ui=out,audio=audio.poll(),event_protocol=2,instance=instance}}
 elseif d.action=='publish' then
  local ok,out=capability.call('publish_app',{app_id='music_player'},{max_output_bytes=2048});return {json={ok=ok,result=out}}
 end
 return {status=400,json={ok=false}}
end)
print('[music] receiver ready')
local ok,err=xpcall(function()app:serve_forever()end,debug.traceback)
audio.close();if not ok then error(err)end

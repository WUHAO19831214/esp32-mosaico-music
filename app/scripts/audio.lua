-- The receiver owns audio too: the factory runtime permits only four Lua jobs.
local audio=require('audio')
local storage=require('storage')
local json=require('json')
local thread=require('thread')
local A={state='idle'}
local output,player
function A.close()
 if player then pcall(player.close,player);player=nil end
 if output then pcall(output.close,output);output=nil end
end
function A.command(d)
 local ok,err=pcall(function()
  if d.action=='tone'then
   A.close();output=assert(audio.open_output());assert(output:set_volume(math.floor(math.max(0,math.min(100,d.volume or 30)))));assert(output:play_tone(523,400));A.close();A.state='idle';A.error=nil
  elseif d.action=='play' then
   A.close();output=assert(audio.open_output());assert(output:set_volume(math.floor(math.max(0,math.min(100,d.volume or 30)))))
   player=assert(audio.player({output=output}));assert(player:play(d.url));A.state='playing';A.error=nil
  elseif d.action=='stop' then A.close();A.state='idle';A.error=nil
  elseif d.action=='volume' and output then assert(output:set_volume(math.floor(math.max(0,math.min(100,d.volume or 30)))))
  elseif d.action=='pause' and player then assert(player:pause());A.state='paused'
  elseif d.action=='resume' and player then assert(player:resume());A.state='playing' end
 end)
 if not ok then A.close();A.state='error';A.error=tostring(err):sub(1,160);return nil,A.error end
 return true
end
function A.poll()
 if player then
  local ok,p=pcall(player.poll,player)
  if not ok then A.error=tostring(p);A.state='error';A.close()
  elseif p.state=='finished' then A.state='finished';A.close()
  elseif p.state=='error' then A.error='设备音频解码或网络请求失败';A.state='error';A.close()
  else A.music_info=p.music_info end
  local raw=storage.read_file(storage.join_path(storage.get_root_dir(),'apps','pomodoro_clock','alarm.json'))
  if raw then
   local good,a=pcall(json.decode,raw)
   if good and a.status=='ringing'then
    local found,info=thread.get('pomodoro_clock_alarm')
    if found and info:find('status=running',1,true)then A.close();A.state='interrupted';A.error='音乐已停止，让番茄时钟响铃'end
   end
  end
 end
 return {state=A.state,error=A.error,music_info=A.music_info}
end
return A

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
process.env.ENABLE_GENERAL_UNBLOCK = 'false';
const api = require('@neteasecloudmusicapienhanced/api');
const QR = require('qrcode');
const {helper,HostPlayer}=require('./audio.cjs');
const {pathToFileURL}=require('node:url');
const ROOT = path.resolve(__dirname, '..');
const DATA = path.join(ROOT, '.local'); fs.mkdirSync(DATA, {recursive:true, mode:0o700});
const configPath = path.join(DATA, 'config.json');
let config;
try { config = JSON.parse(fs.readFileSync(configPath)); } catch {
  config = {device_host:process.env.ESP32_HOST||'', token:crypto.randomBytes(24).toString('hex')};
  fs.writeFileSync(configPath, JSON.stringify(config), {mode:0o600});
}
fs.writeFileSync(path.join(ROOT,'app/config.json'), JSON.stringify({token:config.token}), {mode:0o600});
let cookie = ''; try { cookie = fs.readFileSync(path.join(DATA,'session'), 'utf8'); } catch {}
let profile = null, qrKey = null, qrCreated = 0, qrView=null, lastQrCheck=0, qrChecking=false;
const csrf = crypto.randomBytes(24).toString('hex');
let queue = [], index = -1, results = [], lists = [], target = 'mac';
let deviceResultOffset=0,deviceListOffset=0;
let resultSeq=0;const PAGE_SIZE=3;
let current = null, status = 'idle', position = 0, volume = 30, error = '', revision = 0;
let deviceOnline = false, deviceError = '', browserSeen = 0, deviceSeen = 0;
let command = null, commandNumber = 0, lastEvent = '', lastDeviceRevision = '';
let lyrics = [], browserError = '', songGeneration = 0, operationTail = Promise.resolve();
let initialDeviceSync=true;
const hostPlayer=new HostPlayer();
let hardware={host:'当前 Mac',outputs:[],devices:[],speech:{}},hardwareBusy=false,audioBusy=false,audioMessage='';
let outputUID='',outputName='',btAddress='';
let voice={state:'idle',text:'',message:'',seq:0};
const preferencesPath=path.join(DATA,'playback.json');
try {const p=JSON.parse(fs.readFileSync(preferencesPath));if(['mac','esp32','bluetooth'].includes(p.target))target=p.target;if(Number.isFinite(p.volume))volume=Math.max(0,Math.min(100,p.volume));outputUID=p.outputUID||'';outputName=p.outputName||'';btAddress=p.btAddress||'';}catch{}
function savePreferences(){fs.writeFileSync(preferencesPath,JSON.stringify({target,volume,outputUID,outputName,btAddress}),{mode:0o600});}
function outputStatus(){
 if(target==='esp32')return {target,name:'ESP32 机身扬声器',available:deviceOnline,confirmed:deviceOnline};
 const route=hardware.outputs.find(d=>d.uid===outputUID);
 return {target,uid:outputUID,address:btAddress,name:route?.name||outputName||'尚未选择音频设备',available:!!route,confirmed:!!route&&(!hostPlayer.child||hostPlayer.uid===outputUID)};
}
async function refreshHardware(scan=false){
 if(hardwareBusy)return;hardwareBusy=true;
 try{const d=await helper(scan?'scan':'status','',scan?25000:20000);const merged=new Map((scan?[]:hardware.devices).map(x=>[x.address,x]));for(const x of d.devices)merged.set(x.address,x);hardware={...d,devices:[...merged.values()]};
  if(target==='mac'&&!outputUID){const b=hardware.outputs.find(x=>x.builtin);if(b){outputUID=b.uid;outputName=b.name;savePreferences();}}
 }catch(e){audioMessage=e.message;}finally{hardwareBusy=false;}
}
async function connectBluetooth(address){
 if(audioBusy)throw new Error('正在处理音频设备，请稍候');
 if(!hardware.devices.some(x=>x.address===address))throw new Error('请先扫描并选择列表中的设备');
 audioBusy=true;audioMessage='正在连接所选音箱…';
 (async()=>{try{const d=await helper('connect',address,90000);await serial(async()=>{await stopForRouteChange();target='bluetooth';outputUID=d.route.uid;outputName=d.route.name;btAddress=address;savePreferences();audioMessage=`已确认输出：${outputName}`;revision++;});await refreshHardware();}catch(e){audioMessage=e.message;error=e.message;}finally{audioBusy=false;}})();
}
async function voiceSearch(){
 if(!['idle','done','error'].includes(voice.state))throw new Error('正在处理语音，请稍候');
 error='';voice={state:'permission',text:'',message:'请在 Mac 允许语音识别',seq:Date.now()};
 (async()=>{const file=path.join(DATA,'voice.wav');try{
   let auth=await helper('status','',20000);if(!auth.speech.authorized)auth=await helper('speech-authorize','',90000);
   if(!auth.speech?.authorized)throw new Error('请在 Mac 系统设置中允许音乐助手进行语音识别');
   if(!auth.speech.local)throw new Error('本机尚未就绪中文离线识别，请在 macOS 下载中文听写语言');
   await serial(()=>transport('pause'));voice={...voice,state:'recording',message:'请对 ESP32 说歌名，录音 4 秒'};
   await device('voice',{action:'record'},12000);
   const r=await fetch(`http://${config.device_host}/files/apps/music_player/voice.wav`,{headers:{Connection:'close'},signal:AbortSignal.timeout(10000)});if(!r.ok)throw new Error('未能读取设备录音');fs.writeFileSync(file,Buffer.from(await r.arrayBuffer()),{mode:0o600});
   voice={...voice,state:'recognizing',message:'正在本机识别…'};const d=await helper('transcribe',file,38000);const text=d.text.replace(/[。！？!?]+$/g,'').trim();await serial(()=>search(text));voice={state:'done',message:'已识别：'+text,text,seq:Date.now()};
  }catch(e){voice={...voice,state:'error',message:e.message,seq:Date.now()};error=e.message;}finally{try{fs.unlinkSync(file);}catch{}try{await device('voice',{action:'clear'});}catch{}}})();
}
function toneFile(){const file=path.join(DATA,'test-tone.wav');if(fs.existsSync(file))return file;const rate=22050,count=Math.floor(rate*.4),buffer=Buffer.alloc(44+count*2);buffer.write('RIFF');buffer.writeUInt32LE(buffer.length-8,4);buffer.write('WAVEfmt ',8);buffer.writeUInt32LE(16,16);buffer.writeUInt16LE(1,20);buffer.writeUInt16LE(1,22);buffer.writeUInt32LE(rate,24);buffer.writeUInt32LE(rate*2,28);buffer.writeUInt16LE(2,32);buffer.writeUInt16LE(16,34);buffer.write('data',36);buffer.writeUInt32LE(count*2,40);for(let i=0;i<count;i++)buffer.writeInt16LE(Math.round(6000*Math.sin(2*Math.PI*523.25*i/rate)*Math.min(1,i/200,(count-i)/200)),44+i*2);fs.writeFileSync(file,buffer,{mode:0o600});return file;}
function serial(fn) { const run=operationTail.then(fn,fn); operationTail=run.catch(()=>{}); return run; }
const short = (s,n=70) => Array.from(String(s||'')).slice(0,n).join('');
function song(s) { return {id:String(s.id),name:short(s.name),artist:short((s.ar||s.artists||[]).map(x=>x.name).join(' / ')),album:short((s.al||s.album||{}).name),cover:(s.al||s.album||{}).picUrl||'',duration:(s.dt||s.duration||0)/1000}; }
async function call(name, args={}) {
  const r = await api[name]({...args,cookie,unblock:false,timeout:12000});
  const b = r.body;
  if (!b || (b.code !== undefined && ![200,800,801,802,803].includes(b.code))) throw new Error(b?.message || b?.msg || '网易云请求失败');
  return b;
}
function parseLrc(raw='') {
  const out=[];
  for (const line of raw.split('\n')) {
    const text=line.replace(/\[[^\]]*\]/g,'').trim();
    if(!text) continue;
    for(const m of line.matchAll(/\[(\d+):(\d+(?:\.\d+)?)\]/g)) out.push({t:Number(m[1])*60+Number(m[2]),text:short(text,140)});
  }
  return out.sort((a,b)=>a.t-b.t);
}
function lyricAt(t) { let v=''; for(const l of lyrics) {if(l.t>t)break;v=l.text;} return v; }
async function device(route, body, timeout=6000) {
  const r=await fetch(`http://${config.device_host}/api/lua/music_player/${route}`,{method:'POST',headers:{'Content-Type':'application/json','Connection':'close'},body:JSON.stringify({token:config.token,...body}),signal:AbortSignal.timeout(timeout)});
  if(!r.ok) throw new Error(`设备接口 HTTP ${r.status}`);
  const b=await r.json(); if(!b.ok) throw new Error(b.error||'设备操作失败');return b;
}
function snapshot() {
  return {ok:true,profile:profile?{nickname:profile.nickname}:null,target,current,status,position,volume,results,lists,queue,index,revision,error,lyric:lyricAt(position),deviceOnline,deviceError,browserOnline:Date.now()-browserSeen<6000,browserError,command,audio:{...hardware,busy:audioBusy||hardwareBusy,message:audioMessage,selected:outputStatus()},voice};
}
function browserCmd(action,extra={}) { command={id:++commandNumber,action,...extra}; }
async function transport(action) {
  if(!current && action!=='stop')return;
  if(target==='esp32') await device('audio',{action,volume}); else hostPlayer.send(action);
  status=action==='pause'?'paused':action==='stop'?'idle':'playing'; revision++;
}
async function play(selected) {
  const generation=++songGeneration;
  error='';
  const b=await call('song_url',{id:selected.id,br:128000});
  const item=b.data?.[0];
  if(!item?.url)throw new Error('这首歌当前账号无法播放，请换歌或登录有权限的账号');
  if(item.freeTrialInfo)throw new Error('接口只返回试听片段，请在官方客户端确认账号权限');
  const url=new URL(item.url); if(!['http:','https:'].includes(url.protocol))throw new Error('无效音频地址');
  if(target!=='esp32'&&url.protocol==='http:'&&(/(^|\.)music\.126\.net$|(^|\.)music\.163\.com$/).test(url.hostname))url.protocol='https:';
  if(generation!==songGeneration)return;
  if(target==='esp32') {
    hostPlayer.close();
    browserCmd('stop'); await device('audio',{action:'play',url:url.href,volume});
  } else {
    if(!outputStatus().available)throw new Error('所选音频设备未连接，请到设置页选择并确认输出');
    if(deviceOnline) await device('audio',{action:'stop'});
    browserCmd('stop');await hostPlayer.play(outputUID,url.href,volume);
  }
  current=selected;index=queue.findIndex(s=>s.id===selected.id);position=0;status=target==='mac'?'loading':'playing';revision++;
  lyrics=[]; call('lyric',{id:selected.id}).then(b=>{if(generation===songGeneration)lyrics=parseLrc(b.lrc?.lyric)}).catch(()=>{});
}
async function search(q) {
  if(typeof q!=='string'||!q.trim()||q.length>120)throw new Error('请输入歌名或歌手');
  const b=await call('cloudsearch',{keywords:q.trim(),limit:20,type:1});
  results=(b.result?.songs||[]).map(song);deviceResultOffset=0;resultSeq++;error='';revision++;return results;
}
async function select(id) { const s=[...results,...queue].find(x=>x.id===String(id));if(!s)throw new Error('请重新搜索并选歌');if(!queue.some(x=>x.id===s.id))queue=[...results];await play(s); }
async function startQr() {
  const b=await call('login_qr_key',{timestamp:Date.now()});qrKey=b.data.unikey;qrCreated=Date.now();
  const link=`https://music.163.com/login?codekey=${encodeURIComponent(qrKey)}`;
  const matrix=QR.create(link,{errorCorrectionLevel:'L'}).modules;
  qrView={size:matrix.size,bits:Array.from(matrix.data).join(''),message:'使用网易云 App 扫码'};
  return {image:await QR.toDataURL(link,{width:280,margin:3,errorCorrectionLevel:'L'}),expiresIn:180};
}
async function checkQr() {
  if(profile&&!qrKey)return {code:803,profile:{nickname:profile.nickname}};
  if(!qrKey||Date.now()-qrCreated>180000){if(qrView)qrView.message='二维码已过期，请刷新';return {code:800};}
  if(qrChecking)return {code:801};qrChecking=true;
  try {
    const b=await call('login_qr_check',{key:qrKey,timestamp:Date.now()});
    if(qrView)qrView.message=({800:'二维码过期，请刷新',801:'等待手机扫码',802:'请在手机上确认登录',803:'已登录'})[b.code]||'等待登录';
    if(b.code===803&&b.cookie){cookie=b.cookie;fs.writeFileSync(path.join(DATA,'session'),cookie,{mode:0o600});const s=await call('login_status',{timestamp:Date.now()});profile=s.data?.profile||s.profile||null;qrKey=null;revision++;}
    return {code:b.code,profile:profile?{nickname:profile.nickname}:null};
  }finally{qrChecking=false;}
}
async function next(delta=1) {if(queue.length) await play(queue[(Math.max(0,index)+delta+queue.length)%queue.length]);}
async function changeTarget(value,uid='') {
  if(!['mac','esp32'].includes(value))throw new Error('请从设备列表连接蓝牙音箱');
  if(value==='mac'){const out=hardware.outputs.find(x=>x.uid===uid)||(!uid&&hardware.outputs.find(x=>x.builtin));if(!out)throw new Error('所选输出设备已离线');uid=out.uid;outputName=out.name;}
  if(value===target&&(value==='esp32'||uid===outputUID))return;
  await stopForRouteChange();target=value;if(uid)outputUID=uid;savePreferences();audioMessage='已选择：'+outputStatus().name;error='';revision++;
  // Do not silently restart a track on another speaker.
}
async function stopForRouteChange(){try{if(target==='esp32'&&!deviceOnline)status='idle';else await transport('stop');}catch(e){if(target!=='esp32')throw e;deviceOnline=false;deviceError='原设备停止状态未确认：'+e.message;status='idle';}hostPlayer.close();}
async function action(d) {
  if(d.action==='search')return {results:await search(d.q)};
  if(d.action==='select')await select(d.id);
  else if(d.action==='next')await next(1);
  else if(d.action==='prev')await next(-1);
  else if(d.action==='toggle'){if(status==='idle'||status==='error'){if(current)await play(current);}else await transport(status==='playing'?'pause':'resume');}
  else if(['pause','resume','stop'].includes(d.action))await transport(d.action);
  else if(d.action==='target')await changeTarget(d.target,d.uid);
  else if(d.action==='volume') {volume=Math.max(0,Math.min(100,Number(d.value)||0));if(target==='esp32')await device('audio',{action:'volume',volume});else if(hostPlayer.child)hostPlayer.send('volume',{volume});savePreferences();revision++;}
  else if(d.action==='audio-refresh'){refreshHardware().catch(()=>{});}
  else if(d.action==='bt-scan'){if(hardwareBusy)throw new Error('正在扫描，请稍候');audioMessage='扫描附近可发现的音箱…';refreshHardware(true).then(()=>{if(!audioMessage.includes('失败'))audioMessage='扫描完成，请选择设备';});}
  else if(d.action==='bt-connect')await connectBluetooth(d.address);
  else if(d.action==='bt-disconnect'){if(btAddress)await helper('disconnect',btAddress,10000);hostPlayer.close();status='idle';await refreshHardware();audioMessage='蓝牙已断开，当前不会改用其他扬声器';}
  else if(d.action==='voice')await voiceSearch();
  else if(d.action==='speech-authorize'){helper('speech-authorize','',90000).then(()=>refreshHardware()).catch(e=>{error=e.message;});}
  else if(d.action==='audio-test'){await transport('stop');if(target==='esp32'){await device('audio',{action:'tone',volume});}else{if(!outputStatus().available)throw new Error('请先选择在线的音频设备');await hostPlayer.play(outputUID,pathToFileURL(toneFile()).href,volume);status='testing';}audioMessage='已发送试听音，请确认所选设备出声';}
  else if(d.action==='login')return startQr();
  else if(d.action==='devicepage') {
    const all=d.kind==='lists'?lists:results;
    const offset=Math.max(0,Math.min(Math.max(0,Math.floor((all.length-1)/PAGE_SIZE)*PAGE_SIZE),Math.floor((Number(d.offset)||0)/PAGE_SIZE)*PAGE_SIZE));
    if(d.kind==='lists')deviceListOffset=offset;else deviceResultOffset=offset;
  }
  else if(d.action==='playlists') {
    if(!profile)throw new Error('请先扫码登录');
    const b=await call('user_playlist',{uid:profile.userId,limit:50});lists=(b.playlist||[]).map(x=>({id:String(x.id),name:short(x.name),count:x.trackCount}));deviceListOffset=0;revision++;
  } else if(d.action==='playlist') {
    const b=await call('playlist_track_all',{id:String(d.id),limit:1000,offset:0});results=(b.songs||[]).map(song);queue=[...results];deviceResultOffset=0;resultSeq++;revision++;
  } else if(d.action==='logout') {
    cookie='';profile=null;qrKey=null;qrView=null;try{fs.unlinkSync(path.join(DATA,'session'))}catch{};revision++;
  } else if(d.action==='open-device')await device('ui',{action:'start'});
  else if(!['search','select'].includes(d.action))throw new Error('未知操作');
  return snapshot();
}
async function readJson(req) {
  let raw='';for await(const c of req){raw+=c;if(Buffer.byteLength(raw)>16384)throw new Error('请求过大');}return JSON.parse(raw||'{}');
}
function json(res,value,status=200) {res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(value));}
function permitted(req) {const host=req.headers.host||'';return /^127\.0\.0\.1:\d+$/.test(host)&&(!req.headers.origin||req.headers.origin===`http://${host}`);}
const server=http.createServer(async(req,res)=>{
 try {
  if(!permitted(req))return json(res,{error:'仅允许本机访问'},403);
  const u=new URL(req.url,'http://127.0.0.1');
  if(req.method==='GET'&&u.pathname==='/api/state')return json(res,snapshot());
  if(req.method==='GET'&&u.pathname==='/api/session')return json(res,{csrf});
  if(req.method==='POST'&&u.pathname.startsWith('/api/')) {
    if(req.headers['x-csrf-token']!==csrf)return json(res,{error:'请刷新页面'},403);
    const d=await readJson(req);
    if(u.pathname==='/api/browser') {
      browserSeen=Date.now();
      if(d.commandId===command?.id) {
        if(d.error){browserError=short(d.error,160);status='error';}
        else {browserError='';}
      }
      return json(res,{ok:true});
    }
    if(u.pathname==='/api/qr') {
      return json(res,await startQr());
    }
    if(u.pathname==='/api/qr/check') {
      return json(res,await checkQr());
    }
    if(u.pathname==='/api/action')return json(res,await serial(()=>action(d)));
    return json(res,{error:'接口不存在'},404);
  }
  if(req.method==='GET'&&['/','/app.js','/style.css'].includes(u.pathname)) {
    const filename=u.pathname==='/'?'index.html':u.pathname.slice(1);
    res.writeHead(200,{'Content-Type':filename.endsWith('.js')?'text/javascript':filename.endsWith('.css')?'text/css':'text/html; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'self'; img-src 'self' data: https:; media-src https: http:; style-src 'self'; script-src 'self'; connect-src 'self'"});
    return res.end(fs.readFileSync(path.join(ROOT,'web',filename)));
  }
  json(res,{error:'页面不存在'},404);
 } catch(e) {error=short(e.body?.message||e.message||'请求失败',160);json(res,{ok:false,error},400);}
});
let bridgeBusy=false;
async function bridge() {
 if(bridgeBusy)return;bridgeBusy=true;
 try {
  if(qrKey&&Date.now()-lastQrCheck>2500){lastQrCheck=Date.now();checkQr().catch(()=>{});}
  const feed={page_size:PAGE_SIZE,result_seq:resultSeq,target,current:current?{id:current.id,name:short(current.name,35),artist:short(current.artist,35),duration:current.duration}:null,status,position:Math.floor(position),volume,lyric:short(lyricAt(position),55),results:results.slice(deviceResultOffset,deviceResultOffset+PAGE_SIZE).map(s=>({id:s.id,name:short(s.name,28),artist:short(s.artist,22)})),result_total:results.length,result_offset:deviceResultOffset,lists:lists.slice(deviceListOffset,deviceListOffset+PAGE_SIZE).map(s=>({id:s.id,name:short(s.name,24)})),list_total:lists.length,list_offset:deviceListOffset,profile:profile?short(profile.nickname,16):'',error:short(error,50),audio:{host:short(hardware.host,20),selected:outputStatus(),busy:audioBusy||hardwareBusy,message:short(audioMessage,52),devices:hardware.devices.slice(0,12).map(d=>({address:d.address,name:short(d.name,22),connected:d.connected,paired:d.paired})),outputs:hardware.outputs.filter(d=>!d.bluetooth).map(d=>({uid:d.uid,name:short(d.name,20),builtin:d.builtin})).slice(0,6)},voice};
  // Bound the real byte size for the firmware's 4096-byte queues.
  while(Buffer.byteLength(JSON.stringify(feed))>3950){if(feed.results.length)feed.results.pop();else if(feed.lists.length)feed.lists.pop();else break;}
  const b=await device('sync',{data:feed,qr:qrView,ack:lastEvent});deviceOnline=true;deviceError='';
  if(initialDeviceSync){if(!current)await device('audio',{action:'stop'});initialDeviceSync=false;}
  if(b.audio&&target==='esp32') {
    if(b.audio.state==='finished'&&status==='playing')await serial(()=>next());
    else if(b.audio.state==='error'||b.audio.state==='interrupted') {status='error';error=b.audio.error||'设备解码失败';}
    // The native player does not expose a sample-accurate playback position.
    if(status==='playing')position+=1;
  }
  if(b.event){const eventId=b.event.event_id||b.event.id;if(eventId!==lastEvent){lastEvent=eventId;try{await serial(()=>action(b.event));}catch(e){error=short(e.body?.message||e.message,120);}}}
  deviceSeen=Date.now();
 }catch(e){deviceOnline=false;deviceError=short(e.message,80);}
 finally{bridgeBusy=false;}
}
let hostTickBusy=false;
async function tickHost(){if(hostTickBusy||target==='esp32')return;hostTickBusy=true;try{const p=hostPlayer.state;if(status==='testing'){if(p.state==='finished')status='idle';else if(p.state==='error'){status='error';error=p.error;}}else if(current){position=p.position||0;if(p.state==='finished'&&['playing','loading'].includes(status)){hostPlayer.state={state:'idle',position:0};await serial(()=>next());}else if(p.state==='error'){status='error';error=p.error;}else if(['playing','paused','loading'].includes(p.state))status=p.state;}}catch(e){status='error';error=e.message;}finally{hostTickBusy=false;}}
if(require.main===module) {
 server.listen(Number(process.env.PORT||17863),'127.0.0.1',()=>{fs.writeFileSync(path.join(DATA,'server.pid'),String(process.pid));console.log(`音乐控制台 http://127.0.0.1:${server.address().port}`);});
 if(cookie)call('login_status',{timestamp:Date.now()}).then(s=>{profile=s.data?.profile||s.profile||null}).catch(()=>{});
 setInterval(bridge,1000);bridge();
 setInterval(tickHost,500);
 refreshHardware();setInterval(()=>refreshHardware(),15000).unref();
 process.once('SIGTERM',async()=>{hostPlayer.close();try{if(deviceOnline)await device('audio',{action:'stop'});}catch{}server.close();process.exit(0);});
}
module.exports={parseLrc,song,server,action,snapshot,call};

const {execFile,spawn}=require('node:child_process');
const path=require('node:path'),fs=require('node:fs');
const ROOT=path.resolve(__dirname,'..');
const BINARY=path.join(ROOT,'.local/MosaicoMusicHelper.app/Contents/MacOS/MusicHelper');
function helper(action,value='',timeout=20000){return new Promise((resolve,reject)=>{if(!fs.existsSync(BINARY))return reject(new Error('请先运行 native/build.sh 构建本机音频助手'));const launchApp=true;const result=path.join(ROOT,'.local',`helper-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`);const executable=launchApp?'/usr/bin/open':BINARY;const args=launchApp?['-n','-W',path.resolve(BINARY,'../../..'),'--args',action,value,'--result',result]:[action,value];execFile(executable,args,{cwd:ROOT,timeout,maxBuffer:1024*1024},(err,out)=>{try{if(err)throw new Error(`本机音频助手失败：${err.message}`);const raw=launchApp?fs.readFileSync(result,'utf8'):out.trim().split('\n').at(-1);const b=JSON.parse(raw);if(!b.ok)throw new Error(b.error||'本机音频操作失败');resolve(b);}catch(e){reject(e);}finally{if(launchApp)try{fs.unlinkSync(result);}catch{}}});});}
class HostPlayer{
 constructor(){this.child=null;this.uid='';this.state={state:'idle',position:0};this.pending=null;this.generation=0;}
 async open(uid){if(this.child&&this.uid===uid)return;this.close();const generation=++this.generation;
  await new Promise((resolve,reject)=>{const child=spawn(BINARY,['player',uid],{cwd:ROOT,stdio:['pipe','pipe','pipe']});this.child=child;this.uid=uid;let buf='',ready=false;const timer=setTimeout(()=>{child.kill();reject(new Error('音频输出确认超时'));},8000);
   child.stdout.on('data',chunk=>{buf+=chunk;let split;while((split=buf.indexOf('\n'))>=0){const line=buf.slice(0,split);buf=buf.slice(split+1);try{const d=JSON.parse(line);if(!d.ok){this.state={state:'error',error:d.error};if(!ready){clearTimeout(timer);reject(new Error(d.error));}}else if(d.ready){ready=true;clearTimeout(timer);resolve();}else if(generation===this.generation)this.state=d;}catch{}}});
   child.on('error',e=>{clearTimeout(timer);reject(e);});child.on('exit',()=>{clearTimeout(timer);if(generation===this.generation){this.child=null;if(this.state.state!=='idle')this.state={state:'error',error:'音频播放进程已退出'};}if(!ready)reject(new Error('无法打开所选音频输出'));});
  });
 }
 async play(uid,url,volume){await this.open(uid);this.state={state:'loading',position:0,uid};this.send('play',{url,volume});}
 send(action,extra={}){if(!this.child){if(action==='stop')return;throw new Error('本机播放器尚未启动，请重新选歌');}this.child.stdin.write(JSON.stringify({action,...extra})+'\n');if(action==='pause')this.state={...this.state,state:'paused'};if(action==='stop')this.state={state:'idle',position:0};}
 close(){++this.generation;if(this.child){this.child.stdin.end(JSON.stringify({action:'quit'})+'\n');const child=this.child;setTimeout(()=>{if(child.exitCode===null)child.kill();},1500).unref();}this.child=null;this.uid='';this.state={state:'idle',position:0};}
}
module.exports={helper,HostPlayer};

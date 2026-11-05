const test=require('node:test');const assert=require('node:assert/strict');
const {parseLrc,song,server}=require('../host/server.cjs');
test('LRC multiple timestamps, fraction and stable order',()=>assert.deepEqual(parseLrc('[00:02.50][00:01] 同一句\n[ar:歌手]\n[00:04]后一句'),[{t:1,text:'同一句'},{t:2.5,text:'同一句'},{t:4,text:'后一句'}]));
test('Search and playlist metadata normalize to the same track shape',()=>{const s=song({id:12,name:'歌曲',ar:[{name:'歌手'}],al:{name:'专辑'},dt:10000});assert.equal(s.id,'12');assert.equal(s.artist,'歌手');assert.equal(s.duration,10);});
test('Only same-origin local requests can change playback',async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
 try{let r=await fetch(base+'/api/action',{method:'POST',headers:{'content-type':'application/json'},body:'{"action":"stop"}'});assert.equal(r.status,403);
 r=await fetch(base+'/api/session',{headers:{Origin:'https://example.org'}});assert.equal(r.status,403);
 r=await fetch(base+'/api/state');const b=await r.json();assert.equal(r.status,200);assert.equal(b.cookie,undefined);assert.equal(b.csrf,undefined);
 }finally{await new Promise(r=>server.close(r));}
});

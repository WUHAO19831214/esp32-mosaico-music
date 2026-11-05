"""Install only /apps/music_player using the existing ESP-Claw file APIs."""
from pathlib import Path
import argparse
import hashlib
import json
import socket
import sys
import time
import urllib.parse
import urllib.request
import http.client

ROOT=Path(__file__).resolve().parents[1]
(ROOT/'evidence').mkdir(exist_ok=True)
from device_transport import LOCAL_HTTP, WebIM

REMOTE='/apps/music_player'
_host=None
def host():
    global _host
    if _host:return _host
    cfg=json.loads((ROOT/'.local/config.json').read_text())
    hint=cfg['device_host']
    if not hint:raise ConnectionError('请先运行 node host/configure.cjs <设备IP>')
    req=urllib.request.Request('http://'+hint+'/api/status',headers={'Connection':'close'})
    with LOCAL_HTTP.open(req,timeout=8)as response:status=json.load(response)
    identity=status.get('ap_ssid','').lower()
    if not identity.startswith('esp-claw-')or status.get('wifi_connected')is not True:
        raise ConnectionError('目标不是已联网的 ESP-Claw 设备')
    if cfg.get('device_identity')and cfg['device_identity']!=identity:
        raise ConnectionError('设备身份已变化，请核对后重新运行 configure')
    if not cfg.get('device_identity'):
        cfg['device_identity']=identity
        (ROOT/'.local/config.json').write_text(json.dumps(cfg));(ROOT/'.local/config.json').chmod(0o600)
    _host=hint
    return _host

def native_request(path,data=None,method='GET',content_type=None):
    if isinstance(data,dict):data=json.dumps(data,ensure_ascii=False).encode();content_type='application/json'
    req=urllib.request.Request('http://'+host()+path,data=data,method=method,headers={'Connection':'close',**({'Content-Type':content_type}if content_type else{})})
    attempts=4 if method=='GET'else 1
    for attempt in range(attempts):
        try:
            with LOCAL_HTTP.open(req,timeout=30)as r:return r.read()
        except (OSError,http.client.HTTPException):
            if attempt+1==attempts:raise
            time.sleep(.3*(attempt+1))

def request(route,body=None):
    cfg=json.loads((ROOT/'.local/config.json').read_text())
    return json.loads(native_request('/api/lua/music_player/'+route,{'token':cfg['token'],**(body or {})},'POST'))

def upload(scripts_only=False,only=None):
    # Verify a paired device before writing any file.
    device_host=host()
    cfg=json.loads((ROOT/'.local/config.json').read_text());cfg['device_host']=device_host
    (ROOT/'.local/config.json').write_text(json.dumps(cfg));(ROOT/'.local/config.json').chmod(0o600)
    for directory in [REMOTE,REMOTE+'/scripts',REMOTE+'/assets']:
        assert json.loads(native_request('/api/files/mkdir',{'path':directory,'recursive':True},'POST')).get('ok')
    records=[]
    for p in sorted((ROOT/'app').rglob('*')):
        if not p.is_file():continue
        if scripts_only and p.parent.name!='scripts':continue
        if only and p.relative_to(ROOT/'app').as_posix() not in only:continue
        target=REMOTE+'/'+p.relative_to(ROOT/'app').as_posix();body=p.read_bytes()
        unchanged=False
        # Back up an existing version locally before replacement.
        try:
            old=native_request('/files'+target)
        except Exception as e:
            if getattr(e,'code',None)!=404:raise
        else:
            unchanged=old==body
            if old!=body:
                backup=ROOT/'.local/backups'/time.strftime('%Y%m%d-%H%M%S')/p.relative_to(ROOT/'app')
                backup.parent.mkdir(parents=True,exist_ok=True);backup.write_bytes(old)
                if p.name=='config.json':backup.chmod(0o600)
        if not unchanged:
            print('Uploading',target,len(body),flush=True)
            for attempt in range(3):
                try:
                    out=json.loads(native_request('/api/files/upload?'+urllib.parse.urlencode({'path':target}),body,'POST','application/octet-stream'))
                    assert out.get('ok'),out
                    break
                except Exception as e:
                    if hasattr(e,'read'):print('Upload response:',e.read().decode(errors='replace'),flush=True)
                    if attempt==2:raise
                    time.sleep(.5)
        assert native_request('/files'+target)==body,target
        records.append({'path':target,'bytes':len(body),'sha256':hashlib.sha256(body).hexdigest()})
    (ROOT/'evidence/upload.json').write_text(json.dumps(records,indent=2))
    print('Uploaded and read-back verified',len(records),'files; device',device_host)

def bootstrap():
    # The firmware exposes native Lua start through its device agent.
    try:previous=request('ui',{'action':'status'}).get('instance')
    except Exception:previous=None
    ws=WebIM(host());chat='music-player-install'
    prompt=('请仅启动已上传并校验的音乐应用，不修改任何脚本，也不要操作番茄时钟、AI状态牌或其他任务。'
            '调用 lua_run_script_async，path=/nand/apps/music_player/scripts/receiver.lua，'
            'name=music_player_receiver，exclusive=music_player_receiver，replace=true，timeout_ms=0。'
            '然后用 lua_get_async_job 核实接收服务状态。不要写文件、不要重启设备。')
    print(native_request('/api/webim/send',{'chat_id':chat,'text':prompt},'POST').decode())
    deadline=time.monotonic()+55
    try:
        while time.monotonic()<deadline:
            try:
                r=request('ui',{'action':'status'})
                if r.get('ok')and r.get('event_protocol')==2 and r.get('instance')!=previous:print('Music receiver restarted; event protocol 2');return
            except Exception:pass
            ws.sock.settimeout(2)
            try:
                opcode,body=ws.frame()
                if opcode==1:
                    d=json.loads(body)
                    if d.get('chat_id')==chat:print(str(d.get('text',''))[:1500])
            except socket.timeout:pass
    finally:ws.close()
    raise RuntimeError('设备启动未完成；检查设备原生任务后重试')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['upload','bootstrap','publish','start','stop','status','smoke']);p.add_argument('--scripts',action='store_true');p.add_argument('--only',action='append');p.add_argument('--page',choices=['now','songs','search','account','settings','bluetooth','outputs']);a=p.parse_args()
    if a.action=='upload':upload(a.scripts,a.only)
    elif a.action=='bootstrap':bootstrap()
    else:
        body={'action':{'publish':'publish','start':'start','stop':'stop','status':'status','smoke':'start'}[a.action]}
        if a.action=='smoke':body['args']={'smoke_ms':2500}
        if a.page:body.setdefault('args',{})['page']=a.page
        print(json.dumps(request('ui',body),ensure_ascii=False))

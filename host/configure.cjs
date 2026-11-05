const fs=require('node:fs'),path=require('node:path'),net=require('node:net'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),file=path.join(root,'.local/config.json');
const host=process.argv[2];if(!net.isIP(host||'')){console.error('用法：node host/configure.cjs <ESP32 的局域网 IP>');process.exit(1);}
fs.mkdirSync(path.dirname(file),{recursive:true,mode:0o700});let config={token:crypto.randomBytes(24).toString('hex')};try{config=JSON.parse(fs.readFileSync(file));}catch{}
if(config.device_host!==host)delete config.device_identity;
config.device_host=host;fs.writeFileSync(file,JSON.stringify(config,null,2),{mode:0o600});
fs.writeFileSync(path.join(root,'app/config.json'),JSON.stringify({token:config.token}),{mode:0o600});console.log('已保存本机设备地址和配对配置；未输出令牌。');

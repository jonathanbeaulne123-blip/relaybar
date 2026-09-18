const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),P=require('../../BrowserExtension/protocol.js');
const source=fs.readFileSync(__dirname+'/../../BrowserExtension/background.js','utf8');
const ID='a'.repeat(32),sheet='sheet_123456789',pageToken='12345678-1234-1234-1234-123456789abc';
function fixture(){
 const handlers={},out=[],sent=[],navigations=[]; let tab={id:7,windowId:2,url:`https://docs.google.com/spreadsheets/d/${sheet}/edit`},focus=true;
 const add=k=>({addListener:f=>handlers[k]=f});
 const native={postMessage:m=>out.push(m),onMessage:add('native'),onDisconnect:add('disconnect'),disconnect:()=>{}};
 const chrome={runtime:{id:ID,getURL:()=>`chrome-extension://${ID}/`,connectNative:()=>native,onMessage:add('message')},action:{setBadgeText:()=>Promise.resolve()},storage:{local:{set:async()=>{},get:async()=>({enabled:true})}},
 tabs:{query:async()=>[tab],goBack:async id=>navigations.push(['back',id]),goForward:async id=>navigations.push(['forward',id]),reload:async id=>navigations.push(['reload',id]),sendMessage:async(...a)=>{sent.push(a);return{accepted:true}},onActivated:add('activate'),onUpdated:add('update'),onRemoved:add('remove')},windows:{get:async()=>({focused:focus}),onFocusChanged:add('focus')}};
 const sandbox={chrome,RBPolicy:P,importScripts:()=>{},setInterval:()=>1,clearInterval:()=>{},Date,Map,Set,console};vm.createContext(sandbox);vm.runInContext(source,sandbox);
 const sender={id:ID,tab,frameId:5,url:'https://n-test-script.googleusercontent.com/userCodeAppPanel'};
 const message=(data,who=sender)=>new Promise(resolve=>handlers.message(data,who,resolve));
 const manifest={version:1,sheetID:sheet,pageToken,title:'Test',actions:[{id:'menu:run',label:'Run',confirmation:true}]};
 return {handlers,out,sent,navigations,chrome,manifest,sender,message,get tab(){return tab},set tab(v){tab=v},set focus(v){focus=v}};
}
const flush=()=>new Promise(r=>setImmediate(r));
function command(){return{version:1,sessionID:'12345678-1234-1234-1234-123456789def',requestID:'87654321-1234-1234-1234-123456789def',tabID:7,windowID:2,sheetID:sheet,pageToken,actionID:'menu:run',expiresAt:Date.now()/1000+3};}
async function ready(){const f=fixture();await flush();await f.message({type:'RB_MANIFEST',manifest:f.manifest});return f;}
test('worker accepts real authorized iframe manifest',async()=>{const f=await ready();assert.equal(f.out.at(-1).context.actions.length,1);assert.equal(f.sent.length,0);});
test('worker rejects unrelated iframe origin',async()=>{const f=fixture();await flush();assert.equal((await f.message({type:'RB_MANIFEST',manifest:f.manifest},{...f.sender,url:'https://evil.example/'})).ok,false);});
test('worker rejects top-level page',async()=>{const f=fixture();await flush();assert.equal((await f.message({type:'RB_MANIFEST',manifest:f.manifest},{...f.sender,frameId:0})).ok,false);});
test('worker rejects other extension',async()=>{const f=fixture();await flush();assert.equal((await f.message({type:'RB_MANIFEST',manifest:f.manifest},{...f.sender,id:'b'.repeat(32)})).ok,false);});
test('webpage cannot enable the link',async()=>{const f=fixture();await flush();assert.equal((await f.message({type:'SET_ENABLED',enabled:true})).ok,false);});
test('native tap goes only to exact linked iframe',async()=>{const f=await ready();const c=command();f.handlers.native({sessionID:c.sessionID,command:c});await flush();assert.equal(f.sent.length,1);assert.equal(f.sent[0][0],7);assert.equal(f.sent[0][2].frameId,5);});
test('duplicate native tap not replayed',async()=>{const f=await ready();const c=command();f.handlers.native({sessionID:c.sessionID,command:c});await flush();f.handlers.native({sessionID:c.sessionID,command:c});await flush();assert.equal(f.sent.length,1);});
test('focus loss blocks native command',async()=>{const f=await ready();f.focus=false;const c=command();f.handlers.native({sessionID:c.sessionID,command:c});await flush();assert.equal(f.sent.length,0);});
test('tab navigation clears old manifest before tap',async()=>{const f=await ready();f.handlers.update(7,{status:'loading'});const c=command();f.handlers.native({sessionID:c.sessionID,command:c});await flush();assert.equal(f.sent.length,0);});
test('unlinked frame cannot keep script controls',async()=>{const f=await ready();await f.message({type:'RB_UNLINK'});assert.equal(f.out.at(-1).context.actions.length,0);});
test('two simultaneously linked frames fail closed',async()=>{const f=await ready();assert.equal((await f.message({type:'RB_MANIFEST',manifest:f.manifest},{...f.sender,frameId:6})).ok,false);});
test('disabled extension rejects browser commands',async()=>{const f=await ready();await f.message({type:'SET_ENABLED',enabled:false},{id:ID,url:`chrome-extension://${ID}/popup.html`});const c=command();f.handlers.native({sessionID:c.sessionID,command:c});await flush();assert.equal(f.sent.length,0);});

test('competing sidebar heartbeats stay fail-closed until one disconnects',async()=>{
 const f=await ready(), other={...f.sender,frameId:6};
 assert.equal((await f.message({type:'RB_MANIFEST',manifest:f.manifest},other)).ok,false);
 assert.equal(f.out.at(-1).context.actions.length,0);
 assert.equal((await f.message({type:'RB_MANIFEST',manifest:f.manifest})).ok,false);
 assert.equal((await f.message({type:'RB_MANIFEST',manifest:f.manifest},other)).ok,false);
 const c=command();f.handlers.native({sessionID:c.sessionID,command:c});await flush();assert.equal(f.sent.length,0);
 await f.message({type:'RB_UNLINK'},other);
 assert.equal((await f.message({type:'RB_MANIFEST',manifest:f.manifest})).ok,true);
 assert.equal(f.out.at(-1).context.actions.length,1);
});

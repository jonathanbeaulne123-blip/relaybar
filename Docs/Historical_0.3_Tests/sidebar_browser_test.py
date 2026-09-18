"""Real Chromium DOM tests with explicit Google/Chrome API doubles, offline.
Not a native-extension, Google authorization, Apps Script runtime or Mac test.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright
import json, uuid, shutil
ROOT = Path(__file__).resolve().parents[2]
checks = []
mock = r'''<script>
window.testCalls=[];window.extensionMessages=[];window.extensionListener=null;
const fixture={version:1,sheetID:'sheet_123456789',pageToken:'12345678-1234-1234-1234-123456789abc',title:'Example workbook (test fixture)',actions:[{id:'menu:read',label:'Open planner',confirmation:true},{id:'menu:dialog',label:'Open shift dialog',confirmation:false}],warnings:[]};
function runner(success,fail){return new Proxy({}, {get:(_,key)=>{
 if(key==='withSuccessHandler')return f=>runner(f,fail);
 if(key==='withFailureHandler')return f=>runner(success,f);
 return (...args)=>{window.testCalls.push({name:key,args});setTimeout(()=>{if(success)success(key==='RelayBarGetManifest'?fixture:{ok:true})},5)};
}})}
window.google={script:{run:runner()}};
window.chrome={runtime:{id:'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',onMessage:{addListener:f=>window.extensionListener=f},sendMessage:async m=>{window.extensionMessages.push(m);return{ok:true}}}};
</script>'''
def verify(condition, label):
    assert condition, label
    checks.append(label)
def command(action='menu:read', **extras):
    return dict(version=1,requestID=str(uuid.uuid4()),sheetID='sheet_123456789',pageToken='12345678-1234-1234-1234-123456789abc',actionID=action,**extras)
with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=shutil.which('chromium') or None, headless=True, args=['--no-sandbox'])
    context = browser.new_context(viewport={'width':340,'height':880}, device_scale_factor=1)
    requests = []
    context.route('**/*', lambda route:(requests.append(route.request.url),route.abort()))
    page=context.new_page()
    html=(ROOT/'AppsScript/RelayBarSidebar.html').read_text().replace('<script>\n(() => {', mock+'<script>\n(() => {',1)
    page.set_content(html)
    verify(page.locator('#relaybar-link-v1').get_attribute('data-connected')=='false','Starts disconnected')
    verify(page.evaluate('testCalls.length')==0,'No Google call before consent')
    page.add_script_tag(path=str(ROOT/'BrowserExtension/protocol.js'))
    page.add_script_tag(path=str(ROOT/'BrowserExtension/sidebar.js'))
    page.wait_for_timeout(40)
    verify(page.evaluate('extensionMessages.length')==0,'No manifest published before consent')
    page.click('#connect'); page.wait_for_function("document.querySelector('#relaybar-link-v1').dataset.connected==='true'")
    verify(page.locator('#buttons li').count()==2,'All fixture buttons rendered')
    verify(page.locator('#buttons').inner_text().find('one tap')>=0,'One-tap action is explicitly labelled')
    page.wait_for_function("extensionMessages.some(m=>m.type==='RB_MANIFEST')")
    verify(page.evaluate("testCalls.filter(c=>c.name==='RelayBarInvoke').length")==0,'Connecting does not run a script')
    def tap(c):
        return page.evaluate("""c=>{c.expiresAt=Date.now()/1000+3;let response;extensionListener({type:'RB_RUN',command:c},{id:chrome.runtime.id},r=>response=r);return response;}""",c)
    c=command(); verify(tap(c)['accepted'],'Actual content-script receiver accepts current action')
    verify(page.locator('#question').is_visible(),'Default action asks for confirmation')
    verify(page.evaluate("testCalls.filter(c=>c.name==='RelayBarInvoke').length")==0,'No execution before confirmation')
    evidence=ROOT/'Docs/Evidence_0.3';evidence.mkdir(exist_ok=True)
    page.screenshot(path=str(evidence/'sidebar-confirmation-fixture.png'),full_page=True)
    page.click('#cancel'); verify(page.locator('#question').is_hidden(),'Cancel dismisses request')
    verify(page.evaluate("testCalls.filter(c=>c.name==='RelayBarInvoke').length")==0,'Cancellation never runs script')
    c=command();tap(c);page.click('#confirm');page.wait_for_function("testCalls.some(c=>c.name==='RelayBarInvoke')")
    page.wait_for_function("document.querySelector('#status').textContent==='Script finished.'")
    verify(page.evaluate("testCalls.filter(c=>c.name==='RelayBarInvoke').length")==1,'Confirmed tap runs once')
    verify(tap(c)['accepted']==False,'Content script blocks duplicate request')
    d=command('menu:dialog');tap(d);page.wait_for_function("testCalls.filter(c=>c.name==='RelayBarInvoke').length===2")
    page.wait_for_function("document.querySelector('#status').textContent==='Script finished.'")
    verify(page.locator('#question').is_hidden(),'Reviewed one-tap action skips confirmation')
    wrong=command();wrong['pageToken']='99999999-1234-1234-1234-123456789abc'
    verify(tap(wrong)['accepted']==False,'Different sidebar token rejected')
    wrong=command();wrong['sheetID']='other_sheet_12345'
    verify(tap(wrong)['accepted']==False,'Different workbook rejected')
    page.click('#disconnect');page.wait_for_timeout(20)
    verify(tap(command())['accepted']==False,'Disconnected sidebar rejects taps')
    verify(page.evaluate("testCalls.some(c=>c.name==='RelayBarDisconnect')"),'Disconnect revokes server session')
    verify(page.locator('#buttons li').count()==0,'Disconnect removes published buttons')
    verify(len(requests)==0,'No network requests during offline test')
    page.screenshot(path=str(evidence/'sidebar-disconnected-fixture.png'),full_page=True)
    browser.close()
print(json.dumps({'environment':'Chromium DOM, Google/Chrome API doubles, offline','passed':len(checks),'checks':checks},indent=2))

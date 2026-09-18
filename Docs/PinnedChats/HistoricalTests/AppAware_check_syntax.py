"""Syntax and manifest checks. Does not compile AppKit or install an extension."""
from pathlib import Path
import subprocess, json, plistlib, tempfile, re
r=Path(__file__).resolve().parents[2]
checks=[]
def run(args):
    subprocess.run(args,check=True,cwd=r)
run(['swiftc','-frontend','-parse','-swift-version','5',*map(str,sorted((r/'Sources/Core').glob('*.swift'))),*map(str,sorted((r/'Sources/Mac').glob('*.swift')))])
checks.append('All Swift Core/Mac sources parsed in Swift 5 mode; this is NOT macOS SDK compilation.')
sh=list(r.glob('*.command'))+list((r/'Scripts').glob('*.sh'))
for p in sh: run(['bash','-n',str(p)])
checks.append(f'{len(sh)} shell files passed bash -n; Mac installers not executed.')
js=list((r/'BrowserExtension').glob('*.js'))+list((r/'Tests/AppAware').glob('*.cjs'))
for p in js: run(['node','--check',str(p)])
checks.append(f'{len(js)} JavaScript source/test files passed node --check.')
with tempfile.TemporaryDirectory() as d:
    gs=Path(d)/'RelayBar.cjs';gs.write_text((r/'AppsScript/RelayBar.gs').read_text());run(['node','--check',str(gs)])
    for idx,script in enumerate(re.findall(r'<script>([\s\S]*?)</script>',(r/'AppsScript/RelayBarSidebar.html').read_text())):
        p=Path(d)/f'sidebar-{idx}.js';p.write_text(script);run(['node','--check',str(p)])
checks.append('Actual .gs source and inline sidebar JavaScript parsed; this is NOT Google V8 execution.')
m=json.loads((r/'BrowserExtension/manifest.json').read_text());info=plistlib.loads((r/'Resources/Info.plist').read_bytes())
assert m['manifest_version']==3 and m['version']=='0.4.0' and info['CFBundleShortVersionString']=='0.5.0'
assert info['CFBundleVersion']=='7' and info['CFBundleIdentifier']=='local.relaybar'
assert m['permissions']==['nativeMessaging','storage'] and m['incognito']=='not_allowed'
assert set(m['host_permissions'])=={'https://docs.google.com/*','https://chatgpt.com/*','https://claude.ai/*'}
for p in [m['background']['service_worker'],m['action']['default_popup'],*m['content_scripts'][0]['js']]: assert (r/'BrowserExtension'/p).is_file()
checks.append('Native plist and MV3 JSON versions, limited permissions and referenced assets checked.')
print('\n'.join('PASS: '+c for c in checks))

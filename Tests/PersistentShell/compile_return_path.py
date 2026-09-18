#!/usr/bin/env python3
import pathlib, subprocess, tempfile, sys
R=pathlib.Path(__file__).resolve().parents[2]
app=(R/'Sources/Mac/AppMain.swift').read_text()
needle='    private func returnToRelayBar(showPanel shouldShowPanel: Bool) {'
start=app.index(needle)
# Extract method with balanced braces.
i=start
brace=0
seen=False
end=None
while i < len(app):
    c=app[i]
    if c=='{': brace+=1; seen=True
    elif c=='}':
        brace-=1
        if seen and brace==0:
            end=i+1; break
    i+=1
if end is None: raise SystemExit('could not extract returnToRelayBar')
method=app[start:end]
source='''import Foundation
struct ShellState { mutating func returnToRelayBar() {} }
final class NSWorkspace { static let shared = NSWorkspace(); var frontmostApplication: Int? = nil }
final class Harness {
    var shellState = ShellState()
    var overlayEnabled = false
    func refreshShellMenuState() {}
    func rebuildBars() {}
    func refreshAppContext() {}
    func showPanel() {}
    func updateOverlay(for app: Int?) {}
    func setStatus(_ s: String) {}
'''+method+'''\n}\n'''
with tempfile.TemporaryDirectory() as td:
    f=pathlib.Path(td)/'Harness.swift'; f.write_text(source)
    p=subprocess.run(['swiftc','-swift-version','5','-typecheck',str(f)],text=True,capture_output=True)
    if p.returncode:
        sys.stderr.write(p.stdout+p.stderr); raise SystemExit(p.returncode)
print('PASS: exact returnToRelayBar method typechecks with showPanel external label and shouldShowPanel local binding')

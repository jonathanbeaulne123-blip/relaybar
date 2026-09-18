#!/usr/bin/env python3
"""Run the exact Mac controller under explicit workspace/AX service doubles.
This checks Swift typing and asynchronous controller behavior, NOT AppKit, the
Mac AX adapter, Google Sheets, or physical Touch Bar hardware.
"""
from pathlib import Path
import json, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
fixture=(ROOT/'Tests/RelayCoreTests/NativeMenuTests.swift').read_text().split('private final class FakeAX',1)[1].split('final class NativeMenuTests',1)[0]
fixture='final class FakeAX'+fixture
controller=(ROOT/'Sources/Mac/NativeMenuController.swift').read_text().replace('import Cocoa','import Foundation',1)
cancel=(ROOT/'Sources/Mac/NativeAXSource.swift').read_text().split('final class NativeCancellation',1)[1].split('/// Accessed only',1)[0]
cancel='final class NativeCancellation'+cancel
stub=r'''
import Foundation
typealias NativeAXNode = Int
@MainActor final class NSRunningApplication { var processIdentifier: Int32 = 42 }
@MainActor final class NSWorkspace {
 static let shared = NSWorkspace()
 var frontmostApplication: NSRunningApplication? = NSRunningApplication()
}
enum RBBridge { static var permission=true; static func accessibilityTrusted() -> Bool { permission } }
enum Fixtures { static var current=FakeAX(); static var delay=0.0; static var preparations=0 }
final class NativeAXSource: NativeMenuSource {
 typealias Node=Int
 let cancellation: NativeCancellation
 let fixture: FakeAX
 init(cancellation: NativeCancellation) { self.cancellation=cancellation; fixture=Fixtures.current }
 var trusted:Bool { fixture.trusted && !cancellation.cancelled }
 var limited:Bool { fixture.limited || cancellation.cancelled }
 var now:Double { fixture.now }
 func beginRead() { if Fixtures.delay > 0 { Thread.sleep(forTimeInterval:Fixtures.delay) }; fixture.beginRead() }
 func frontmostPID()->Int32 { fixture.frontmostPID() }
 func application(_ pid:Int32)->Int { fixture.application(pid) }
 func element(_ n:Int,_ a:NativeAXAttribute)->Int? { fixture.element(n,a) }
 func string(_ n:Int,_ a:NativeAXAttribute)->String? { fixture.string(n,a) }
 func flag(_ n:Int,_ a:NativeAXAttribute)->Bool? { fixture.flag(n,a) }
 func children(_ n:Int)->[Int]? { fixture.children(n) }
 func rect(_ n:Int)->NativeRect? { fixture.rect(n) }
 func actions(_ n:Int)->[String] { fixture.actions(n) }
 func hitTest(_ n:Int,x:Double,y:Double)->Int? { fixture.hitTest(n,x:x,y:y) }
 func pointerClick(x:Double,y:Double)->Bool { !cancellation.cancelled && fixture.pointerClick(x:x,y:y) }
 func perform(_ n:Int,action:String)->Bool { !cancellation.cancelled && fixture.perform(n,action:action) }
 func prepareBrowser(pid:Int32,bundle:String) { if trusted { Fixtures.preparations += 1 } }
}
'''
main=r'''
import Foundation
@main struct ControllerChecks {
 @MainActor static func main() async {
  var passed:[String]=[]
  func check(_ value:Bool,_ name:String) { if !value { fatalError("FAIL: " + name) }; passed.append(name) }
  func wait(_ predicate:()->Bool) async { for _ in 0..<200 { if predicate() { return }; try? await Task.sleep(nanoseconds:5_000_000) }; fatalError("Timed out waiting for controller") }
  let c=NativeMenuController()
  var notices:[String]=[]; c.onStatus={ notices.append($0) }
  c.observe(pid:42,bundle:"com.google.Chrome",enabled:true)
  await wait { c.snapshot != nil }
  check(c.snapshot?.ready == true,"actual controller accepts native-source fixture")
  check(c.controls.count == 2,"open menu items become controller buttons")
  check(Fixtures.current.presses.isEmpty && Fixtures.current.pointerClicks.isEmpty,"foreground detection performs no actions")
  check(Fixtures.preparations == 1,"browser preparation runs once")
  let rev=c.revision
  c.tap(index:0,expectedRevision:rev)
  check(c.gate.pending != nil,"leaf tap asks inline confirmation")
  check(Fixtures.current.presses.isEmpty && Fixtures.current.pointerClicks.isEmpty,"confirmation does not execute")
  c.confirm(expectedRevision:rev)
  c.confirm(expectedRevision:rev)
  c.tap(index:0,expectedRevision:rev)
  await wait { c.gate.executing == nil }
  check(Fixtures.current.pointerClicks.count == 1 && Fixtures.current.presses.isEmpty,"duplicate confirm/tap cannot cancel or duplicate first request")
  check(c.snapshot == nil,"dispatch invalidates old button snapshot")
  check(notices.last?.contains("completion is not verified") == true,"status does not claim script completion")
  c.observe(pid:42,bundle:"com.google.Chrome",enabled:true)
  await wait { c.snapshot != nil }
  check(Fixtures.preparations == 1,"polling does not repeat browser preparation")
  c.tap(index:0,expectedRevision:rev)
  check(c.gate.pending == nil,"retired revision cannot stage a new action")
  c.tap(index:0,expectedRevision:c.revision); c.cancelConfirmation()
  check(c.gate.pending == nil,"cancel leaves script untouched")
  c.showMenus()
  check(c.controls.first?.label == "My scripts","Menus returns custom-first root list")
  let count=Fixtures.current.pointerClicks.count
  c.askBeforeActions=false; Fixtures.delay=0.05
  c.tap(index:0,expectedRevision:c.revision); c.clear()
  try? await Task.sleep(nanoseconds:150_000_000)
  check(Fixtures.current.pointerClicks.count == count,"clear cancels queued dispatch before native action")
  check(c.snapshot == nil,"retired callback cannot restore cleared context")
  Fixtures.delay=0
  c.observe(pid:42,bundle:"com.google.Chrome",enabled:false)
  check(c.snapshot == nil,"paused controller does not inspect")
  let d=NativeMenuController(); Fixtures.current=FakeAX(); Fixtures.current.trusted=false; RBBridge.permission=false
  d.observe(pid:42,bundle:"com.google.Chrome",enabled:true)
  await wait { d.snapshot != nil }
  check(d.snapshot?.ready == false,"missing permission is a real unavailable state")
  Fixtures.current.trusted=true; RBBridge.permission=true
  try? await Task.sleep(nanoseconds:700_000_000)
  let prepared=Fixtures.preparations
  d.observe(pid:42,bundle:"com.google.Chrome",enabled:true)
  await wait { d.snapshot?.ready == true }
  check(Fixtures.preparations == prepared+1,"granting permission later still prepares the browser")
  check(!d.connectionReport.contains("WORKBOOK_1") && !d.connectionReport.contains("PRIVATE CELL"),"report excludes document URL and cell fixture")
  d.tap(index:0,expectedRevision:d.revision); d.suspend()
  check(d.gate.pending == nil,"app or screenshot interruption cancels pending confirmation")
  let e=NativeMenuController(); Fixtures.current=FakeAX(open:false); RBBridge.permission=true
  Fixtures.current.tree[6]?.flags[.enabled]=nil; Fixtures.current.hit=6
  Fixtures.current.afterPerform={ node,action in
    if node == 6 {
      Fixtures.current.add(9,"AXGroup",children:[10,11])
      Fixtures.current.add(10,"AXMenuItem","Hearth action one")
      Fixtures.current.add(11,"AXMenuItem","Hearth action two")
      Fixtures.current.tree[3]?.kids?.append(9); Fixtures.current.fixParents()
    }
  }
  e.observe(pid:42,bundle:"com.google.Chrome",enabled:true)
  await wait { e.snapshot?.ready == true }
  check(e.controls.first?.label == "My scripts","custom menu trigger is available without explicit AXEnabled")
  e.tap(index:0,expectedRevision:e.revision)
  await wait { e.gate.executing == nil }
  e.observe(pid:42,bundle:"com.google.Chrome",enabled:true)
  await wait { e.snapshot?.openItems.count == 2 }
  check(e.controls.map(\.label) == ["Hearth action one","Hearth action two"],"menu tap expands lazy generic popup into Touch Bar actions")
  Fixtures.current.hit=10
  let actionRev=e.revision; e.tap(index:0,expectedRevision:actionRev)
  check(e.gate.pending != nil,"expanded Hearth action still uses leaf confirmation")
  e.confirm(expectedRevision:actionRev)
  await wait { e.gate.executing == nil }
  check(Fixtures.current.pointerClicks.count >= 2,"expanded Hearth action revalidates and dispatches through same verified-click policy")
  let data=try! JSONSerialization.data(withJSONObject:["passed":passed.count,"failed":0,"checks":passed,"boundary":"Exact controller, explicit workspace/AX doubles. Not native macOS or browser testing."],options:[.prettyPrinted,.sortedKeys])
  print(String(decoding:data,as:UTF8.self))
 }
}
'''
with tempfile.TemporaryDirectory(prefix='relaybar-controller-') as temp:
    t=Path(temp)
    (t/'Stubs.swift').write_text(stub+fixture+cancel)
    (t/'Controller.swift').write_text(controller)
    (t/'Main.swift').write_text(main)
    run=subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(ROOT/'Sources/Core/NativeMenus.swift'),str(t/'Stubs.swift'),str(t/'Controller.swift'),str(t/'Main.swift'),'-o',str(t/'check')],capture_output=True,text=True,timeout=45)
    if run.returncode: raise SystemExit(run.stdout+run.stderr)
    if run.stderr: print(run.stderr)
    run=subprocess.run([str(t/'check')],capture_output=True,text=True,timeout=20)
    if run.returncode: raise SystemExit(run.stdout+run.stderr)
    print(run.stdout)

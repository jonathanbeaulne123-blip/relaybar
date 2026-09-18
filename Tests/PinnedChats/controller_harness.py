#!/usr/bin/env python3
"""Compile/run the exact Pins controller with explicit Cocoa/AX service doubles.
NOT a macOS SDK typecheck, actual Accessibility scan, or Touch Bar test.
"""
from pathlib import Path
import subprocess,tempfile,json
R=Path(__file__).resolve().parents[2]
controller=(R/'Sources/Mac/PinnedChatsMac.swift').read_text().replace('import Cocoa','import Foundation',1)
stub=r'''
import Foundation
final class Anchor { func constraint(equalTo:Anchor,constant:Double)->NSLayoutConstraint { NSLayoutConstraint() } }
class NSView {
 let leadingAnchor=Anchor(),trailingAnchor=Anchor(),topAnchor=Anchor()
 var translatesAutoresizingMaskIntoConstraints=false
 func addSubview(_ v:NSView) {}
}
final class NSLayoutConstraint { static func activate(_ values:[NSLayoutConstraint]) {} }
class NSTextField:NSView { var stringValue=""; var isSelectable=false }
enum Orient { case vertical }; enum Align { case leading }
class NSStackView:NSView { var orientation=Orient.vertical; var alignment=Align.leading; var spacing:Double=0; init(views:[NSView]){} }
struct Masks:OptionSet { let rawValue:Int; static let titled=Masks(rawValue:1),closable=Masks(rawValue:2) }
enum Backing { case buffered }; enum Weight { case semibold }
class NSPanel { var title=""; var isReleasedWhenClosed=false; var contentView:NSView?=NSView()
 init(contentRect:NSRect,styleMask:Masks,backing:Backing,defer:Bool){}
 func center(){};func close(){};func orderOut(_ s:Any?){};func orderFront(_ s:Any?){}
}
func label(_ s:String,size:Double=13,weight:Weight = .semibold)->NSTextField { let x=NSTextField();x.stringValue=s;return x }
class ActionButton:NSView { init(_ title:String,action:@escaping()->Void){} }
func row(_ views:[NSView])->NSView { NSView() }
@MainActor class NSRunningApplication {
 var processIdentifier:pid_t; var bundleIdentifier:String?; var isTerminated=false
 init(_ pid:pid_t=42,_ bundle:String="com.openai.chat"){processIdentifier=pid;bundleIdentifier=bundle}
}
@MainActor class NSWorkspace {
 static let shared=NSWorkspace();static let willSleepNotification=Notification.Name("sleep")
 let notificationCenter=NotificationCenter();var frontmostApplication:NSRunningApplication?=NSRunningApplication()
}
enum RBBridge { static func requestAccessibility(){} }
class TouchBarDriver {
 struct Slot { var key:String;var title:String;var help:String;var isEnabled:Bool;var width:Double;var action:()->Void
 init(key:String,title:String,help:String,isEnabled:Bool=true,width:Double=60,action:@escaping()->Void){self.key=key;self.title=title;self.help=help;self.isEnabled=isEnabled;self.width=width;self.action=action}
 }
}
final class PinnedChatsAXReader {
 struct Request {var pid:pid_t;var bundle:String;var nativeProvider:PinProvider?}
 struct Sample {var session:PinSession;var inventory:PinInventory}
 enum Outcome {case ready(Sample);case unavailable(String)}
 static let browsers:Set<String>=["com.google.Chrome"]
 static var scans=0,presses=0;static var delay=0.0;static var failure:String?;static var reason:String?
 static var replacement:[PinnedChat]?
 func scan(_ r:Request)->Outcome {
  Self.scans += 1;if Self.delay>0 {Thread.sleep(forTimeInterval:Self.delay)}
  if let s=Self.reason{return .unavailable(s)}
  let chats=Self.replacement ?? (0..<7).map {PinnedChat(token:"c\($0)",identity:"u\($0)",title:"Work \($0)",url:nil,selected:$0==0,enabled:true,evidence:"fixture")}
  return .ready(Sample(session:PinSession(pid:r.pid,bundle:r.bundle,window:"w",document:"d",provider:r.nativeProvider ?? .chatgpt),inventory:PinInventory(chats:chats,recognizedSection:true,limited:false,ambiguous:0)))
 }
 func forget(){}
 @MainActor static func press(_ chat:PinnedChat,in fresh:Sample,expected:Sample)->String? {presses += 1;return failure}
}
'''
main=r'''
import Foundation
@main struct Checks {
 @MainActor static func main() async {
  var passed:[String]=[]
  func check(_ b:Bool,_ n:String){if !b {fatalError("FAIL: "+n)};passed.append(n)}
  func sleep(_ ns:UInt64=80_000_000) async{try? await Task.sleep(nanoseconds:ns)}
  func wait(_ f:()->Bool) async {for _ in 0..<300{if f(){return};await sleep(5_000_000)};fatalError("wait timeout")}
  let c=PinnedChatsController(); var updates=0;c.onChange={updates += 1}
  func slots()->[TouchBarDriver.Slot]{c.slots(back:{},hide:{})}
  func buttons()->[TouchBarDriver.Slot]{slots().filter{$0.key.hasPrefix("pin-")}}
  func poll(){c.update(front:NSWorkspace.shared.frontmostApplication,nativeProvider:.chatgpt,force:true)}
  check(PinnedChatsAXReader.scans==0,"initialization does not read the app")
  c.update(front:NSWorkspace.shared.frontmostApplication,nativeProvider:.chatgpt,force:true)
  await sleep();check(PinnedChatsAXReader.scans==0,"inactive update does not read")
  c.start();poll();await wait{buttons().count==3}
  check(PinnedChatsAXReader.presses==0,"discovery never navigates")
  check(slots().first{$0.key=="pins-next"}?.title=="1/3 ›","seven actual entries have three pages")
  check(buttons().first?.title.contains("✓")==true,"selected chat marker carried into the real slots")
  check(slots().reduce(0){$0+$1.width}<=600,"Pins widths remain within compact budget")
  slots().first{$0.key=="pins-next"}!.action();check(buttons().first?.help.hasPrefix("4.")==true,"next page exposes fourth chat")
  slots().first{$0.key=="pins-prev"}!.action();check(buttons().first?.help.hasPrefix("1.")==true,"previous page returns first chat")
  let old=buttons()[0]
  old.action();old.action();check(buttons().allSatisfy{!$0.isEnabled},"pending dispatch disables chat buttons")
  await wait{PinnedChatsAXReader.presses==1}
  check(c.message.contains("Navigation requested"),"success says request, not loaded chat")
  check(buttons().isEmpty,"dispatch retires the inventory")
  poll();await wait{buttons().count==3};old.action();await sleep()
  check(PinnedChatsAXReader.presses==1,"old-generation button cannot open another chat")
  PinnedChatsAXReader.replacement=[];buttons()[0].action();await wait{buttons().isEmpty}
  check(PinnedChatsAXReader.presses==1,"fresh unpin rejects navigation")
  PinnedChatsAXReader.replacement=nil;poll();await wait{buttons().count==3}
  let x=buttons()[0];NSWorkspace.shared.frontmostApplication=NSRunningApplication(43,"com.anthropic.claudefordesktop")
  x.action();await sleep();check(PinnedChatsAXReader.presses==1,"foreground change rejects stale tap")
  c.update(front:NSWorkspace.shared.frontmostApplication,nativeProvider:.claude,force:true);await wait{c.provider == .claude}
  check(buttons().count==3,"provider switch replaces the inventory")
  var switched:PinProvider?;c.onSwitchProvider={switched=$0}
  slots().first{$0.key.hasPrefix("pins-provider-")}!.action()
  check(switched == .chatgpt,"provider button explicitly asks to open other assistant")
  check(buttons().isEmpty,"switch clears old provider targets immediately")
  NSWorkspace.shared.frontmostApplication=NSRunningApplication();poll();await wait{buttons().count==3}
  PinnedChatsAXReader.delay=0.05;buttons()[0].action();c.stop();await sleep(140_000_000)
  check(PinnedChatsAXReader.presses==1,"stop cancels queued navigation before action")
  check(buttons().isEmpty,"late callback does not repopulate stopped page")
  PinnedChatsAXReader.delay=0;c.start();poll();await wait{buttons().count==3}
  PinnedChatsAXReader.failure="AX request timed out";buttons()[0].action();await wait{PinnedChatsAXReader.presses==2}
  await sleep();check(PinnedChatsAXReader.presses==2,"uncertain action is never automatically retried")
  PinnedChatsAXReader.reason="No sidebar exposed";poll();await wait{c.message=="No sidebar exposed"}
  check(buttons().isEmpty,"unavailable source produces status not invented pins")
  c.showStatus();c.stopForTermination();check(buttons().isEmpty,"termination discards in-memory pins")
  check(updates>0,"real controller notifies native view refresh")
  print(String(data:try! JSONSerialization.data(withJSONObject:["passed":passed.count,"failed":0,"checks":passed,"boundary":"Exact controller with explicit Cocoa and AX reader doubles; not Mac or live sidebar execution."],options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
 }
}
'''
with tempfile.TemporaryDirectory() as t:
 p=Path(t);(p/'Stub.swift').write_text(stub);(p/'Controller.swift').write_text(controller);(p/'Main.swift').write_text(main)
 command=['swiftc','-swift-version','5','-parse-as-library',str(R/'Sources/Core/PinnedChats.swift'),str(p/'Stub.swift'),str(p/'Controller.swift'),str(p/'Main.swift'),'-o',str(p/'run')]
 subprocess.run(command,check=True,capture_output=False)
 out=subprocess.run([str(p/'run')],check=True,capture_output=True,text=True,timeout=20).stdout
 result=json.loads(out);print(out)
 target=R/'Docs/PinnedChats/CONTROLLER_FIXTURE_RESULTS.json';target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(result,indent=2)+'\n')

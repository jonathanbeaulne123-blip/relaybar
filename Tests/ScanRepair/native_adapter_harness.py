#!/usr/bin/env python3
"""Execute unchanged adapter/engine bodies using explicit Foundation/C-API doubles.
Only the import lines are changed. This is not macOS SDK validation, native IPC,
or a live Chrome/Sheets test. Also reproduce failures against exact v0.5 files.
"""
from pathlib import Path
import subprocess, tempfile, json, shutil, sys
R=Path(__file__).resolve().parents[2]
STUB=r'''
import Foundation
// Foundation-only service doubles; not Apple's C types or implementations.
typealias CFTypeRef = AnyObject
typealias CFString = NSString
typealias CFArray = NSArray
typealias CFURL = NSURL
typealias CFIndex = Int
typealias DarwinBoolean = ObjCBool
let kCFBooleanTrue: NSNumber = NSNumber(value:true)
let kAXChildrenAttribute = "AXChildren", kAXPositionAttribute = "AXPosition", kAXSizeAttribute = "AXSize"
struct AXCopyMultipleAttributeOptions: OptionSet { let rawValue: UInt32 }
enum AXError { case success, attributeUnsupported, noValue, cannotComplete }
final class AXUIElement: NSObject { let id:Int; init(_ id:Int) {self.id=id}; override var hash:Int{id}; override func isEqual(_ o:Any?)->Bool{(o as? AXUIElement)?.id==id} }
enum AXValueType { case cgPoint, cgSize, axError }
final class AXValue: NSObject { let type:AXValueType; let point:CGPoint; let size:CGSize
 init(_ p:CGPoint){type = .cgPoint;point=p;size = .zero}; init(_ s:CGSize){type = .cgSize;size=s;point = .zero}
 override init(){type = .axError;point = .zero;size = .zero}
}
func CFEqual(_ a:AnyObject,_ b:AnyObject)->Bool{(a as? NSObject)?.isEqual(b) ?? false}
func CFHash(_ a:AnyObject)->Int{(a as? NSObject)?.hash ?? 0}
func AXUIElementGetTypeID()->Int{1}; func CFURLGetTypeID()->Int{2};func CFStringGetTypeID()->Int{3};func AXValueGetTypeID()->Int{4}
func CFGetTypeID(_ a:AnyObject)->Int{if a is AXUIElement{return 1};if a is NSURL{return 2};if a is NSString{return 3};if a is AXValue{return 4};return 9}
func CFURLGetString(_ u:CFURL)->CFString?{u.absoluteString as NSString?}
func AXValueGetType(_ v:AXValue)->AXValueType{v.type}
func AXValueGetValue(_ v:AXValue,_ t:AXValueType,_ p:UnsafeMutableRawPointer)->Bool{
 if t == .cgPoint {p.assumingMemoryBound(to:CGPoint.self).pointee=v.point;return true}
 if t == .cgSize {p.assumingMemoryBound(to:CGSize.self).pointee=v.size;return true};return false
}

enum CGEventSourceStateID { case combinedSessionState }
enum CGMouseButton { case left }
enum CGEventType { case leftMouseDown, leftMouseUp }
enum CGEventTapLocation { case cghidEventTap }
final class CGEventSource {
 static func buttonState(_ state:CGEventSourceStateID, button:CGMouseButton)->Bool { API.leftButtonDown }
}
final class CGEvent {
 let kind:CGEventType; let point:CGPoint
 init?(mouseEventSource:CGEventSource?, mouseType:CGEventType, mouseCursorPosition:CGPoint, mouseButton:CGMouseButton){kind=mouseType;point=mouseCursorPosition}
 func post(tap:CGEventTapLocation){API.clickEvents += 1}
}
final class NSRunningApplication {var processIdentifier:Int32 = 42}
final class NSWorkspace {static let shared=NSWorkspace();var frontmostApplication:NSRunningApplication?=NSRunningApplication()}
enum API {
 struct Item {var role:String;var subrole:String?=nil;var hidden:Bool?=nil;var kids:[Int]=[];var attrs:[String:AnyObject]=[:];var actions:[String]=["AXPress"]}
 static var tree:[Int:Item]=[:], trust=true, batchUnsupported=false, batchMissingRole=false, malformedBatch=false
 static var shortPage=false, changeCount=false, duplicate=false, leftButtonDown=false, countCalls=0, copies=0, batches=0, reads=0, presses=0, clickEvents=0
 static var hit:Int?=10, beforeHit:(()->Void)?=nil
 static func reset(){tree=[:];trust=true;batchUnsupported=false;batchMissingRole=false;malformedBatch=false;shortPage=false;changeCount=false;duplicate=false;countCalls=0;copies=0;batches=0;reads=0;presses=0;clickEvents=0;leftButtonDown=false;hit=10;beforeHit=nil;NSWorkspace.shared.frontmostApplication?.processIdentifier=42}
 static func add(_ id:Int,_ role:String,_ kids:[Int]=[],label:String=""){
  tree[id]=Item(role:role,kids:kids,attrs:["AXTitle":label as NSString,"AXEnabled":NSNumber(value:true),"AXPosition":AXValue(CGPoint(x:10,y:10)),"AXSize":AXValue(CGSize(width:100,height:28))])
 }
 static func fixture(noise:Int=0,wide:Int=0,toolbar:Bool=false){reset()
  add(0,"AXApplication");add(1,"AXWindow",[3]);add(3,"AXWebArea",[4,7,9]);add(4,"AXMenuBar",[5,6]);add(5,"AXMenuItem",label:"File");add(6,"AXMenuItem",label:"My scripts")
  add(7,"AXTable",[8]);add(8,"AXCell",label:"PRIVATE CELL VALUE");add(9,"AXMenu",[10,11]);add(10,"AXMenuItem",label:"Harmless fixture");add(11,"AXMenuItem",label:"Other fixture")
  tree[0]?.attrs["AXFocusedWindow"]=AXUIElement(1);tree[0]?.attrs["AXFocusedUIElement"]=AXUIElement(7)
  tree[3]?.attrs["AXURL"]="https://docs.google.com/spreadsheets/d/PRIVATE_WORKBOOK/edit#gid=0" as NSString
  for n in [1,3]{tree[n]?.attrs["AXPosition"]=AXValue(CGPoint.zero);tree[n]?.attrs["AXSize"]=AXValue(CGSize(width:1200,height:800))}
  if noise>0 {for i in 0..<noise {let kids=(1...3).map{3*i+$0}.filter{$0<noise}.map{10000+$0};add(10000+i,"AXGroup",kids)};tree[3]?.kids.insert(10000,at:0)}
  if wide>0 {let kids=Array(20000..<(20000+wide));add(90,toolbar ? "AXToolbar":"AXGroup",kids);for id in kids{add(id,"AXStaticText",label:"PRIVATE TEXT")};tree[3]?.kids.insert(90,at:0)}
  for (id,item) in tree{for kid in item.kids{tree[kid]?.attrs["AXParent"]=AXUIElement(id)}}
 }
 static func attribute(_ id:Int,_ name:String)->AnyObject? {
  guard let t=tree[id] else{return nil};switch name {
  case "AXRole":return t.role as NSString
  case "AXSubrole":return t.subrole as NSString?
  case "AXHidden":return t.hidden.map{NSNumber(value:$0)}
  default:return t.attrs[name]
  }
 }
}
func AXIsProcessTrusted()->Bool{API.trust}
func AXUIElementCreateApplication(_ pid:Int32)->AXUIElement{AXUIElement(0)}
@discardableResult func AXUIElementSetMessagingTimeout(_ e:AXUIElement,_ t:Float)->AXError{.success}
func AXUIElementCopyAttributeValue(_ e:AXUIElement,_ n:CFString,_ out:inout CFTypeRef?)->AXError{API.reads+=1;out=API.attribute(e.id,n as String);return out == nil ? .noValue:.success}
func AXUIElementCopyMultipleAttributeValues(_ e:AXUIElement,_ names:CFArray,_ options:AXCopyMultipleAttributeOptions,_ out:inout CFArray?)->AXError{
 API.batches+=1;if API.batchUnsupported{return .attributeUnsupported}
 var values=(names as! [String]).map{API.attribute(e.id,$0) ?? AXValue()}
 if API.batchMissingRole{values[0]=AXValue()};if API.malformedBatch{values.removeLast()};out=values as NSArray;return .success
}
func AXUIElementGetAttributeValueCount(_ e:AXUIElement,_ n:CFString,_ out:inout CFIndex)->AXError{
 API.countCalls+=1;guard let t=API.tree[e.id] else{return .cannotComplete};out=t.kids.count
 if API.changeCount && API.countCalls>1{out+=1};return .success
}
func AXUIElementCopyAttributeValues(_ e:AXUIElement,_ name:CFString,_ offset:CFIndex,_ count:CFIndex,_ out:inout CFArray?)->AXError{
 API.copies+=1;guard let t=API.tree[e.id],offset>=0,count>=0,offset+count<=t.kids.count else{return .cannotComplete}
 var nodes=Array(t.kids[offset..<(offset+count)]).map(AXUIElement.init)
 if API.shortPage && !nodes.isEmpty{nodes.removeLast()}
 if API.duplicate && nodes.count>1{nodes[1]=nodes[0]};out=nodes as NSArray;return .success
}
func AXUIElementCopyActionNames(_ e:AXUIElement,_ out:inout CFArray?)->AXError{out=(API.tree[e.id]?.actions ?? []) as NSArray;return .success}
func AXUIElementCopyElementAtPosition(_ e:AXUIElement,_ x:Float,_ y:Float,_ out:inout AXUIElement?)->AXError{API.beforeHit?();out=API.hit.map(AXUIElement.init);return out == nil ? .noValue:.success}
func AXUIElementPerformAction(_ e:AXUIElement,_ a:CFString)->AXError{API.presses+=1;return .success}
func AXUIElementIsAttributeSettable(_ e:AXUIElement,_ a:CFString,_ out:inout DarwinBoolean)->AXError{out=false;return .success}
func AXUIElementSetAttributeValue(_ e:AXUIElement,_ a:CFString,_ v:CFTypeRef)->AXError{.success}
'''
MAIN=r'''
import Foundation
@main struct NativeAdapterChecks {
 static func main() {
  var checks:[String]=[]
  func check(_ v:Bool,_ name:String){if !v{fatalError("FAIL: "+name)};checks.append(name)}
  func source()->NativeAXSource{NativeAXSource(cancellation:NativeCancellation())}
  API.fixture();let s=source();let n=NativeAXNode(AXUIElement(4))
  check(s.header(n).role == "AXMenuBar","batched role decoded")
  check(s.header(n).subrole == nil && s.header(n).hidden == nil,"optional AXError sentinels not misread as visibility")
  _=s.string(n,.role);_=s.flag(n,.hidden)
  check(API.batches==1 && API.reads==0,"shape metadata read once and cached per scan")
  s.beginRead();_=s.header(n);check(API.batches==2,"new scan invalidates shape cache")
  API.fixture();API.batchUnsupported=true;let fallback=source()
  check(fallback.header(n).role == "AXMenuBar" && fallback.metrics.headerFallbacks==1,"unsupported batching uses scalar fallback")
  API.fixture();API.batchUnsupported=true;let fallbackScan=NativeMenuEngine(source:source()).scan(pid:42,bundle:"com.google.Chrome")
  check(fallbackScan.ready && fallbackScan.readMetrics.headerFallbacks>0,"complete menu scan works through scalar compatibility fallback")
  API.fixture();API.batchMissingRole=true;check(source().header(n).role == "AXMenuBar","missing role in batch safely falls back")
  API.fixture();API.malformedBatch=true;check(source().header(n).role == "AXMenuBar","malformed batch length safely falls back")
  API.fixture();API.tree[4]?.hidden=true;check(source().header(n).hidden==true,"hidden boolean retained")
  API.fixture(wide:300);let wideSource=source();let children=wideSource.children(NativeAXNode(AXUIElement(90)))
  check(children?.count==300 && API.copies==5,"300-child wrapper uses five complete bounded pages")
  check(children?.first?.element.id==20000 && children?.last?.element.id==20299,"paged children preserve ordering without truncation")
  check(wideSource.metrics.widestBranch==300 && wideSource.metrics.childPages==5,"wide-branch metrics reported")
  API.fixture(wide:300);API.shortPage=true;let short=source();check(short.children(NativeAXNode(AXUIElement(90)))==nil && short.metrics.failure == .readFailed,"short page fails closed")
  API.fixture(wide:300);API.changeCount=true;let changing=source();check(changing.children(NativeAXNode(AXUIElement(90)))==nil && changing.metrics.failure == .readFailed,"changing child count fails closed")
  API.fixture(wide:300);API.duplicate=true;check(source().children(NativeAXNode(AXUIElement(90)))==nil,"duplicate child handles fail closed")
  API.fixture(wide:4097);let huge=source();check(huge.children(NativeAXNode(AXUIElement(90)))==nil && huge.metrics.failure == .children,"oversized wrapper still has hard bound")
  API.fixture();let cancelled=NativeCancellation();let cs=NativeAXSource(cancellation:cancelled);cancelled.cancel();check(cs.metrics.failure == .cancelled && cs.children(n)==nil,"cancelled read does no work")
  API.fixture();let q=source();for _ in 0..<5001{_=q.flag(n,.enabled)};check(q.metrics.failure == .queries && q.metrics.queries==5000,"query bound remains 5000")
  API.fixture();let timed=source();Thread.sleep(forTimeInterval:0.87);check(timed.limited && timed.metrics.failure == .deadline,"time budget remains 850ms")
  API.fixture(noise:800);let largeSource=source();let large=NativeMenuEngine(source:largeSource).scan(pid:42,bundle:"com.google.Chrome")
  check(large.ready && large.roots.count==2 && large.openItems.count==2,"800-group tree succeeds within bounded scan limits")
  check(large.readMetrics.queries<5000 && large.failure == .none,"large-tree report identifies successful bounded scan")
  let largeMetrics:[String:Any] = ["nodes":large.nodesVisited,"queries":large.readMetrics.queries,"batches":large.readMetrics.headerBatches,"status":large.status]
  API.fixture(wide:300);let wideScan=NativeMenuEngine(source:source()).scan(pid:42,bundle:"com.google.Chrome")
  check(wideScan.ready,"wide structural wrapper reaches menus after 300 content leaves")
  API.fixture(wide:4097,toolbar:true);let pruning=NativeMenuEngine(source:source()).scan(pid:42,bundle:"com.google.Chrome")
  check(pruning.ready && pruning.prunedChromeNodes==1,"formatting toolbar skipped before massive child-list read")
  check(API.presses==0 && API.clickEvents==0,"discovery never executes an action")
  API.fixture(noise:1800);let limited=NativeMenuEngine(source:source()).scan(pid:42,bundle:"com.google.Chrome")
  check(!limited.ready && limited.failure == .nodes && limited.roots.isEmpty && limited.openItems.isEmpty,"node bound still disables all partially scanned actions")
  API.fixture();API.add(30,"AXGroup");API.tree[30]?.subrole="AXDialog";API.tree[3]?.kids.append(30)
  check(!NativeMenuEngine(source:source()).scan(pid:42,bundle:"com.google.Chrome").ready,"batched dialog subrole still blocks actions")
  API.fixture();let engine=NativeMenuEngine(source:source());let expected=engine.scan(pid:42,bundle:"com.google.Chrome")
  check(engine.request(expected.openItems[0],expected:expected) == .requested && API.clickEvents==2 && API.presses==0,"fresh Chromium target issues one verified click pair")
  API.fixture();let e2=NativeMenuEngine(source:source());let expected2=e2.scan(pid:42,bundle:"com.google.Chrome");API.hit=7
  if case .refused=e2.request(expected2.openItems[0],expected:expected2){check(API.presses==0 && API.clickEvents==0,"covered target refused after fresh scan")}else{fatalError("covered target accepted")}
  API.fixture();let e3=NativeMenuEngine(source:source());let expected3=e3.scan(pid:42,bundle:"com.google.Chrome");API.tree[10]?.attrs["AXTitle"]="Different action" as NSString
  if case .refused=e3.request(expected3.openItems[0],expected:expected3){check(API.presses==0 && API.clickEvents==0,"changed action rejected after cache reset")}else{fatalError("changed action accepted")}
  API.fixture();let e4=NativeMenuEngine(source:source());let expected4=e4.scan(pid:42,bundle:"com.google.Chrome");API.beforeHit={API.trust=false}
  if case .refused=e4.request(expected4.openItems[0],expected:expected4){check(API.presses==0 && API.clickEvents==0,"permission revocation before dispatch blocks action")}else{fatalError("revoked permission accepted")}
  let result:[String:Any]=["passed":checks.count,"failed":0,"checks":checks,"large_fixture":largeMetrics,"boundary":"Actual adapter/engine bodies; explicit Foundation and AX API service doubles. Not Apple SDK, native IPC, live Sheets, or Touch Bar execution."]
  print(String(data:try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
 }
}
'''
LEGACY=r'''
import Foundation
@main struct Legacy {
 static func main(){var rows:[[String:Any]]=[]
 for (label,noise,wide) in [("800-group tree",800,0),("300-child wrapper",0,300)] {
  API.fixture(noise:noise,wide:wide)
  let s=NativeAXSource(cancellation:NativeCancellation());let r=NativeMenuEngine(source:s).scan(pid:42,bundle:"com.google.Chrome")
  rows.append(["fixture":label,"ready":r.ready,"nodes":r.nodesVisited,"roots":r.roots.count,"openItems":r.openItems.count,"status":r.status,"scalarAttributeReads":API.reads,"childCountReads":API.countCalls,"childPageReads":API.copies])
 }
 print(String(data:try! JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
 }
}
'''
def execute(core,adapter,main):
    with tempfile.TemporaryDirectory(prefix='relaybar-ax-fixture-') as d:
        d=Path(d)
        (d/'API.swift').write_text(STUB)
        (d/'Adapter.swift').write_text(adapter.replace('import Cocoa','import Foundation',1).replace('import ApplicationServices','',1))
        (d/'Core.swift').write_text(core)
        (d/'Main.swift').write_text(main)
        p=subprocess.run(['swiftc','-swift-version','5','-parse-as-library',*[str(d/n) for n in ['API.swift','Adapter.swift','Core.swift','Main.swift']],'-o',str(d/'run')],capture_output=True,text=True,timeout=45)
        if p.returncode:raise RuntimeError(p.stdout+p.stderr)
        p=subprocess.run([str(d/'run')],capture_output=True,text=True,timeout=20)
        if p.returncode:raise RuntimeError(p.stdout+p.stderr)
        return json.loads(p.stdout)
if __name__=='__main__':
    new=execute((R/'Sources/Core/NativeMenus.swift').read_text(),(R/'Sources/Mac/NativeAXSource.swift').read_text(),MAIN)
    old=execute((R/'Tests/ScanRepair/Baseline/NativeMenus_0.5.swift').read_text(),(R/'Tests/ScanRepair/Baseline/NativeAXSource_0.5.swift').read_text(),LEGACY)
    assert all(not r['ready'] for r in old),old
    print(json.dumps({'current':new,'baseline':old},indent=2))

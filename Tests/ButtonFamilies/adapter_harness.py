#!/usr/bin/env python3
"""Execute the production family adapter with explicit AppKit/feature doubles.
This is not a macOS SDK build, real sidebar scan, clipboard test or hardware test.
Only `private` visibility is relaxed in the copied adapter to inspect its state.
"""
from pathlib import Path
import subprocess, tempfile, json
ROOT=Path(__file__).resolve().parents[2]
source=(ROOT/'Sources/Mac/AppMain.swift').read_text()
adapter=source.split('// MARK: - Button Families (presentation adapter; existing feature engines unchanged)',1)[1]
adapter=adapter.replace('private func ', 'func ')
# Native-only self-check, when present, is exercised by the separate Mac command.
if '// MARK: - Native family construction checks' in adapter:
    adapter=adapter.split('// MARK: - Native family construction checks',1)[0]
stub=r'''
import Foundation
class NSMenuItem {
 var title:String; var submenu:NSMenu?; var state=State.off
 enum State {case on,off}
 init(title:String="",action:String?=nil,keyEquivalent:String=""){self.title=title}
 static func separator()->NSMenuItem { NSMenuItem(title:"--") }
}
class FamilyMenuItem:NSMenuItem {
 let handler:()->Void
 init(_ title:String,help:String="",handler:@escaping()->Void){self.handler=handler;super.init(title:title)}
 func invoke(){handler()}
}
class NSMenu {var items:[NSMenuItem]=[];init(title:String=""){};func addItem(_ i:NSMenuItem){items.append(i)}}
class FakeText {var string=""}
class FakePanel {var isKeyWindow=false;func makeFirstResponder(_ x:Any?) {}}
class NSAlert {
 enum Response {case alertFirstButtonReturn,alertSecondButtonReturn}
 static var response=Response.alertFirstButtonReturn
 var messageText="",informativeText=""
 func addButton(withTitle:String){}
 func runModal()->Response{Self.response}
}
class NSImage {}
struct FakeActivationOptions: OptionSet { let rawValue:Int; static let activateIgnoringOtherApps = FakeActivationOptions(rawValue:1) }
class FakeRunningApp {
 var bundleIdentifier:String?; var bundleURL:URL?; var isTerminated=false
 init(bundleIdentifier:String?=nil,bundleURL:URL?=nil){self.bundleIdentifier=bundleIdentifier;self.bundleURL=bundleURL}
 func activate(options:FakeActivationOptions)->Bool { true }
}
@MainActor class NSWorkspace {
 class OpenConfiguration { var activates=false }
 static let shared=NSWorkspace();var frontmostApplication:Int?=42;var runningApplications:[FakeRunningApp]=[]
 func openApplication(at:URL, configuration:OpenConfiguration, completionHandler:@escaping(FakeRunningApp?,Error?)->Void){completionHandler(FakeRunningApp(bundleURL:at),nil)}
}
class TouchBarDriver {
 static let flexibleSpaceKey="__relaybar_flexible_space__"
 struct Slot { var key:String;var title:String;var help:String;var image:NSImage?=nil;var isEnabled:Bool=true;var width:CGFloat?;var action:()->Void }
}
@MainActor enum PersistentShellMac {
 static func applicationURL(for app:PersistentShellApp,configuredAssistantURL:URL?=nil)->URL? { configuredAssistantURL ?? URL(fileURLWithPath:"/Applications/\(app.displayName).app") }
 static func icon(for url:URL?)->NSImage? { nil }
}
@MainActor final class NativeDouble {
 struct Snapshot {var openItems:[Int]=[]}
 var snapshot:Snapshot?;var forceRoots=false;var pendingLabel:String?
 var cancellations=0, confirmsCancelled=0, roots=0
 func cancelInteraction(){cancellations += 1;pendingLabel=nil}
 func cancelConfirmation(){confirmsCancelled += 1;pendingLabel=nil}
 func showMenus(){roots += 1;forceRoots=true}
}
@MainActor class PinsDouble {
 var starts=0,stops=0,presses=0,refreshes=0
 func start(){starts += 1};func stop(){stops += 1}
 func slots(back:@escaping()->Void,hide:@escaping()->Void)->[TouchBarDriver.Slot] {
  var s=[TouchBarDriver.Slot(key:"pins-tools",title:"Tools",help:"",width:46,action:back),
         .init(key:"pins-provider-gpt",title:"GPT ⇄",help:"",width:78,action:{}),
         .init(key:"pins-prev",title:"‹",help:"",width:28,action:{})]
  for i in 0..<3{s.append(.init(key:"pin-gen-\(i)",title:"Example \(i)",help:"Chat \(i)",width:102,action:{self.presses += 1}))}
  s += [.init(key:"pins-next",title:"1/2 ›",help:"",width:46,action:{}),.init(key:"pins-refresh",title:"↻",help:"",width:34,action:{self.refreshes += 1}),.init(key:"hide",title:"×",help:"",width:28,action:hide)]
  return s
 }
}
@MainActor class StackDouble {
 struct Session {var collecting=false};var session=Session();var copies=0
 func slots(back:@escaping()->Void,hide:@escaping()->Void)->[TouchBarDriver.Slot]{
  var s:[TouchBarDriver.Slot]=[.init(key:"stack-back",title:"Tools",help:"",width:46,action:back)]
  for i in 0..<3{s.append(.init(key:"stack-clip-\(i)",title:"Excerpt \(i)",help:"Original text \(i)",width:94,action:{self.copies += 1}))}
  s += [.init(key:"stack-pack-rev",title:"Pack 3",help:"Copy ordered full-text handoff",width:64,action:{self.copies += 1}),.init(key:"stack-hide",title:"×",help:"",width:28,action:hide)]
  return s
 }
}
struct ShelfDouble {var watching=false}
@MainActor class RelayAppDelegate {
 var navigation=RelayNavigation(),configuration=AppConfiguration(),capture=Capture.empty
 var draft:PromptDraft?;var draftView:FakeText?=FakeText(),referenceView=FakeText()
 var nativeMenus=NativeDouble(),pinnedChats:PinsDouble?=PinsDouble(),contextStack:StackDouble?=StackDouble()
 var showingContextStack=false,showingPinnedChats=false
 var panel:FakePanel! = FakePanel()
 var screenshotShelf:ShelfDouble?=ShelfDouble(),screenshotPresentation=ScreenshotPresentationState()
 var liveProfile="assistant",appAwareEnabled=true,overlayEnabled=true,nativeMenusEnabled=false,nativeAskActions=true
 var shellState=PersistentShellState()
 var screenshotPageMenuItem:NSMenuItem?,stackSummaryMenuItem:NSMenuItem?,stackCollectMenuItem:NSMenuItem?
 var screenshotWatchMenuItem:NSMenuItem?,screenshotAutoOpenMenuItem:NSMenuItem?,appAwareMenuItem:NSMenuItem?
 var overlayMenuItem:NSMenuItem?,nativePauseMenuItem:NSMenuItem?,nativeAskMenuItem:NSMenuItem?,followMenuItem:NSMenuItem?,desktopMenuItem:NSMenuItem?
 var effects:[String]=[],rebuilds=0,overlays=0,pinReads=0
 func effect(_ s:String){effects.append(s)}
 func returnToRelayBar(showPanel:Bool){shellState.returnToRelayBar();overlayEnabled=true;effect("relayReturn")}
 func enterMacTouchBarMode(){shellState.enterMacMode();overlayEnabled=false;effect("macMode")}
 func appURL(for t:AssistantTarget)->URL?{URL(fileURLWithPath:"/Applications/"+(t == .chatgpt ? "ChatGPT.app":"Claude.app"))}
 func refreshAppContext(){effect("refreshContext")}
 func setStatus(_ s:String){effect("status")}
 func refreshPinnedContext(force:Bool=false){if showingPinnedChats {pinReads += 1}}
 func rebuildBars(){rebuilds += 1}
 func updateOverlay(for app:Int?){overlays += 1}
 func hidePanel(){effect("hidePanel")}
 func stopPinnedChats(){if showingPinnedChats{showingPinnedChats=false;pinnedChats?.stop()}}
 func screenshotSlots()->[TouchBarDriver.Slot]{
  var s:[TouchBarDriver.Slot]=[.init(key:"shotTools",title:"Tools",help:"",width:46,action:{})]
  for i in 0..<5 {s.append(.init(key:"shot-\(i)",title:"\(i+1)",help:"Full-resolution image \(i)",width:78,action:{self.effect("image-\(i)")}))}
  s.append(.init(key:"pins-open",title:"Pins",help:"",width:44,action:{}));return s
 }
 func appAwareSlots(fallback:[TouchBarDriver.Slot])->[TouchBarDriver.Slot]{
  guard liveProfile=="sheets" else{return fallback}
  if nativeMenus.pendingLabel != nil {return [.init(key:"native-confirm-1",title:"Run: synthetic",help:"",width:340,action:{self.effect("confirm")}),.init(key:"native-cancel-1",title:"Cancel",help:"",width:85,action:{self.nativeMenus.cancelConfirmation()})]}
  var s:[TouchBarDriver.Slot]=[.init(key:"stack-open",title:"Stack",help:"",width:44,action:{}),.init(key:"screenshots",title:"Shots",help:"",width:44,action:{})]
  s.append(.init(key:"native-roots",title:"Menus",help:"",width:46,action:{self.nativeMenus.showMenus()}))
  for i in 0..<4{s.append(.init(key:"native-\(i)",title:"Action \(i)",help:"",width:84,action:{self.effect("native-\(i)")}))}
  s += [.init(key:"native-page-1",title:"1/2 ›",help:"",width:58,action:{}),.init(key:"hide",title:"×",help:"",width:28,action:{})]
  return s
 }
 func changeProject(to id:String){configuration.selectedProjectID=id;effect("project-\(id)")}
 func saveConfiguration(){effect("saveConfig")};func refreshControls(){rebuildBars()}
 func showPanel(){effect("showPanel")}
 func refreshPinnedChats(){effect("refreshPins")};func showPinnedStatus(){effect("pinsStatus")}
 func performAction(_ a:PromptAction){effect("prompt-\(a.rawValue)")}
 func captureSelection(){effect("captureSelection")};func captureClipboard(){effect("captureClipboard")};func clearSession(){effect("clearSession")}
 func toggleStackCollection(){contextStack?.session.collecting.toggle();effect("collectStack")}
 func pasteStackClip(){effect("pasteStack")};func reviewStack(){effect("reviewStack")};func clearStack(){effect("clearStack")}
 func chooseScreenshotFolder(){effect("chooseFolder")};func toggleScreenshotWatching(){effect("watchImages")}
 func toggleScreenshotAutoOpen(){effect("autoImages")};func addScreenshotClipboard(){effect("clipboardImage")};func clearScreenshotShelf(){effect("clearImages")}
 func setTarget(_ t:AssistantTarget){configuration.target=t;effect("target-\(t.rawValue)")}
 func openPinnedAssistant(_ p:PinProvider){effect("open-\(p.rawValue)")}
 func copyDraft(){effect("copyDraft")};func copyAndOpen(){effect("copyAndOpen")};func prefillClaude(){effect("prefillClaude")}
 func saveCheckpoint(){effect("saveCheckpoint")};func loadCheckpointFromMenu(){effect("loadCheckpoint")}
 func editProject(isNew:Bool){effect(isNew ? "newProject":"editProject")};func revealData(){effect("revealData")}
 func toggleAppAware(){effect("toggleAppAware")};func toggleOverlay(){effect("toggleOverlay")};func disableOverlay(){effect("disableOverlay")}
 func enableNativeControls(){effect("enableNative")};func toggleNativeDetection(){effect("nativeDetection")};func toggleNativeConfirmation(){effect("nativeConfirmation")}
 func showNativeReport(){effect("nativeReport")};func requestAccessibility(){effect("accessibility")}
 func toggleFollow(){effect("follow")};func toggleDesktop(){effect("desktop")};func chooseApp(_ t:AssistantTarget){effect("chooseApp-\(t.rawValue)")};func showAbout(){effect("about")}
}
'''
main=r'''
@main struct AdapterChecks {
 @MainActor static func main() {
  var checks:[String]=[]
  func check(_ value:Bool,_ name:String){if !value{fatalError("FAIL: "+name)};checks.append(name)}
  let a=RelayAppDelegate()
  func slot(_ suffix:String)->TouchBarDriver.Slot {guard let s=a.familySlots().first(where:{$0.key.hasSuffix(suffix)}) else{fatalError("Missing "+suffix)};return s}
  let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
  let originalConfig=try! encoder.encode(a.configuration)
  for p in RelayPage.allCases {
   a.navigation.open(p)
   let s=a.familySlots()
   check(Set(s.map(\.key)).count==s.count,"unique real adapter keys: "+p.rawValue)
   check(s.reduce(CGFloat(0)){$0+($1.width ?? 0)} + CGFloat(max(0,s.count-1))*6 <= 900,"persistent shell width + gaps budget: "+p.rawValue)
   check(s.suffix(4).last?.key=="shell-mac" && s.last?.title=="","Mac fixed at far right: "+p.rawValue)
   check(s.contains{$0.key==TouchBarDriver.flexibleSpaceKey},"flexible spacer before shell: "+p.rawValue)
   check(p == .home || s[0].key.hasSuffix("family-back"),"Back fixed at left: "+p.rawValue)
  }
  check(a.effects.isEmpty && a.pinReads==0,"building every page is passive")
  check(a.contextStack?.session.collecting==false,"opening/rendering Stack does not collect")
  check((try! encoder.encode(a.configuration))==originalConfig,"rendering never changes configuration")
  a.navigation.home();let root=a.familySlots();check(root.filter{$0.key.hasPrefix("family-")}.count==5,"Home has five contextual groups")
  check(Array(root.suffix(4)).map(\.key)==["shell-app-chrome","shell-app-claude","shell-app-chatgpt","shell-mac"],"persistent app pins and Mac button are fixed at right")
  root.first{$0.key.hasSuffix("group-prompting")}!.action()
  check(a.navigation.page == .prompting,"Prompting group opens child view")
  check(a.effects.isEmpty,"opening group generates no prompt")
  slot("prompt-nextSlice").action();check(a.effects.last=="prompt-nextSlice","Next slice uses original handler")
  slot("prompt-challenge").action();check(a.effects.last=="prompt-challenge","Challenge uses original handler")
  slot("prompt-handoff").action();check(a.effects.last=="prompt-handoff","Handoff uses original handler")
  let retired=slot("prompt-handoff");a.navigate(to:.context);let before=a.effects.count;retired.action()
  check(a.effects.count==before,"retired prompt cannot dispatch after navigation")
  root.first{$0.key.hasSuffix("group-prompting")}!.action();check(a.navigation.page == .context,"retired Home group cannot reroute")
  a.navigate(to:.stack);check(a.contextStack?.session.collecting==false,"entering Stack still does not collect")
  slot("collectStack").action();check(a.contextStack?.session.collecting==true,"Collect is an explicit leaf action")
  slot("stack-pack-rev").action();check(a.contextStack?.copies==1,"Pack reuses exact controller slot closure")
  a.navigate(to:.stackClips);check(a.familySlots().filter{$0.key.contains("stack-clip-")}.count==3,"all three clip buttons retained")
  slot("stack-clip-1").action();check(a.contextStack?.copies==2,"clip copy closure retained")
  a.navigate(to:.screenshots);check(a.familySlots().filter{$0.key.contains("-shot-")}.count==5,"all five image buttons retained")
  slot("shot-4").action();check(a.effects.last=="image-4","fifth image copies its original ID")
  a.navigate(to:.pins);check(a.pinnedChats?.starts==1 && a.pinReads>0,"only explicit Pins leaf starts sidebar detection")
  check(a.familySlots().filter{$0.key.contains("-pin-gen-")}.count==3,"all three pin titles retained")
  let oldPin=slot("pin-gen-0");a.navigate(to:.chats);oldPin.action()
  check(a.pinnedChats?.presses==0 && a.pinnedChats?.stops==1,"leaving Pins stops detection and retires navigation")
  a.navigation.open(.draft);a.draft=nil;check(!slot("copyDraft").isEnabled,"copy disabled without draft")
  a.draft=PromptDraft(text:"test",action:.nextSlice,projectID:"hearth",target:.chatgpt,createdAt:Date());a.draftView?.string="test"
  check(slot("copyDraft").isEnabled,"copy enabled with nonempty draft")
  check(!slot("prefillClaude").isEnabled,"Claude prefill disabled for GPT destination")
  a.configuration.target = .claude;check(slot("prefillClaude").isEnabled,"Claude prefill enabled for Claude destination")
  a.draftView?.string="  ";check(!slot("copyDraft").isEnabled,"empty edited draft disables copy")
  a.nativeMenus.pendingLabel="synthetic";a.nativeMenus.snapshot = .init(openItems:[1]);a.liveProfile="sheets";a.navigation.open(.appControls)
  a.navigateBack();check(a.navigation.page == .appControls && a.nativeMenus.confirmsCancelled==1,"Back cancels pending action without leaving menu")
  a.navigateBack();check(a.navigation.page == .appControls && a.nativeMenus.forceRoots,"Back from open native menu returns roots")
  a.navigateBack();check(a.navigation.page == .workspace,"Back from native roots returns Workspace")
  a.navigate(to:.appControls)
  let nativeSlots=a.familySlots()
  check(!nativeSlots.contains{$0.title=="Stack" || $0.title=="Shots"},"native page has no unrelated capture shortcuts")
  check(nativeSlots.reduce(CGFloat(0)){$0+($1.width ?? 0)}+CGFloat(nativeSlots.count-1)*6<=900,"populated native menu plus shell fits width budget")
  slot("native-2").action();check(a.effects.last=="native-2","native original action closure preserved")
  a.nativeMenus.pendingLabel="synthetic"
  check(a.familySlots().reduce(CGFloat(0)){$0+($1.width ?? 0)}+CGFloat(a.familySlots().count-1)*6<=900,"native confirmation plus shell fits width budget")
  a.navigation.open(.projects);a.configuration.projects=(0..<100).map{.init(id:"p\($0)",name:"Project \($0)",brief:"",constraints:"")};a.configuration.selectedProjectID="p0"
  var seen=Set<String>()
  for p in 0..<25 {a.navigation.setProjectPage(p,count:100);for s in a.familySlots() where s.key.contains("choose-project-"){seen.insert(s.title)} }
  check(seen.count==100,"adapter exposes all 100 project choices")
  a.navigation.setProjectPage(0,count:100);let oldProject=slot("choose-project-p0");slot("projects-page-0-100").action();let prior=a.effects.count;oldProject.action();check(a.effects.count==prior,"retired project-page controls are inert")
  check(a.navigation.projectPage==1,"project pager advances once")
  a.navigation.open(.draft);a.navigation.screenshotArrived(autoOpen:true);a.reconcileNavigation();slot("family-back").action();check(a.navigation.page == .draft,"actual Back adapter resumes interrupted draft")
  let menus=RelayHierarchy.items(on:.home).compactMap{ i->NSMenuItem? in if case .page(let p)=i{return a.familyMenu(p)};return nil }
  check(menus.map(\.title)==["Prompting","Context","Chats","Workspace","Settings"],"RB menu shares exactly the five families")
  check(a.overlayMenuItem != nil && a.stackCollectMenuItem != nil && a.nativeAskMenuItem != nil,"existing stateful RB menu controls remain bound")
  NSAlert.response = .alertFirstButtonReturn;a.runFamilyCommand(.clearSession);check(a.effects.last != "clearSession","Clear session cancel preserves draft")
  NSAlert.response = .alertSecondButtonReturn;a.runFamilyCommand(.clearSession);check(a.effects.last == "clearSession","Clear session requires explicit confirmation")
  a.navigation.home();let persistent=a.familySlots();persistent.first{$0.key=="shell-mac"}!.action();check(a.shellState.mode == .mac && !a.overlayEnabled,"Mac button hands off to stock Touch Bar")
  a.returnToRelayBar(showPanel:false);check(a.shellState.relayVisible && a.overlayEnabled,"explicit return restores persistent RelayBar")
  let chrome=a.familySlots().first{$0.key=="shell-app-chrome"}!;check(chrome.isEnabled,"installed Chrome pin is enabled in adapter fixture");let rb=a.rebuilds;chrome.action();check(a.rebuilds>rb,"Chrome pin enters explicit activation path")
  let result:[String:Any] = ["passed":checks.count,"failed":0,"checks":checks,"boundary":"Actual production family adapter compiled with explicit AppKit and feature doubles. Not a macOS SDK or hardware test."]
  print(String(decoding:try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }
}
'''
with tempfile.TemporaryDirectory(prefix='relaybar-families-') as tmp:
    t=Path(tmp)
    (t/'Stubs.swift').write_text(stub)
    (t/'Adapter.swift').write_text('import Foundation\n'+adapter)
    (t/'Main.swift').write_text('import Foundation\n'+main)
    args=['swiftc','-swift-version','5','-parse-as-library']+[str(p) for p in (ROOT/'Sources/Core').glob('*.swift')]+[str(t/x) for x in ['Stubs.swift','Adapter.swift','Main.swift']]+['-o',str(t/'run')]
    r=subprocess.run(args,capture_output=True,text=True,timeout=45)
    if r.returncode: raise SystemExit(r.stdout+r.stderr)
    if r.stderr: print(r.stderr)
    r=subprocess.run([str(t/'run')],capture_output=True,text=True,timeout=20)
    if r.returncode: raise SystemExit(r.stdout+r.stderr)
    result=json.loads(r.stdout)
    (ROOT/'Docs/ButtonFamilies/ADAPTER_RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print(r.stdout)

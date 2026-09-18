"""Source-contract checks; these are NOT native execution or live UI tests."""
import unittest, pathlib, plistlib, hashlib, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
APP=(ROOT/'Sources/Mac/AppMain.swift').read_text()
AX=(ROOT/'Sources/Mac/PinnedChatsAX.swift').read_text()
MAC=(ROOT/'Sources/Mac/PinnedChatsMac.swift').read_text()
CORE=(ROOT/'Sources/Core/PinnedChats.swift').read_text()
def body(source,signature):
 i=source.index(signature);start=source.index('{',i);level=0
 for j in range(start,len(source)):
  level+=(source[j]=='{')-(source[j]=='}')
  if level==0:return source[start:j+1]
 raise ValueError('unbalanced')
class PinsWiringTests(unittest.TestCase):
 def test_real_controller_instantiated(self): self.assertIn('pinnedChats = PinnedChatsController()',APP)
 def test_pins_page_uses_real_slots(self):
  self.assertIn('let slots = familySlots()',body(APP,'private func rebuildBars()'));self.assertIn('pinnedChats?.slots(',body(APP,'private func familySlots()'))
 def test_primary_chats_family(self):
  catalog=(ROOT/'Sources/Core/ButtonHierarchy.swift').read_text();self.assertIn('case .chats: return [.page(.pins)',catalog)
 def test_browser_entry_without_extension(self): self.assertIn('pinnedChatsSlot()',body(APP,'private func appAwareSlots('))
 def test_screenshot_still_preempts(self): self.assertIn('self.stopPinnedChats()',body(APP,'screenshotShelf?.onChange ='))
 def test_back_to_home_stops_reading(self):
  self.assertIn('navigate(to: .home)',body(APP,'private func showToolsPage()'));self.assertIn('else { stopPinnedChats() }',body(APP,'private func reconcileNavigation()'))
 def test_stack_stops_pins_not_clips(self):
  self.assertIn('navigate(to: .stack)',body(APP,'@objc private func showStackFromMenu()'));self.assertIn('else { stopPinnedChats() }',body(APP,'private func reconcileNavigation()'))
 def test_hide_stops_pins(self): self.assertIn('stopPinnedChats()',body(APP,'@objc private func togglePersistentShellPause()'))
 def test_quit_clears(self): self.assertIn('pinnedChats?.stopForTermination()',body(APP,'func applicationWillTerminate('))
 def test_no_title_based_identity(self):
  b=body(APP,'private func pinnedNativeProvider(')
  self.assertNotIn('localizedName',b);self.assertIn('configuration.appPaths',b);self.assertIn('app.bundleIdentifier',b)
 def test_browsers_have_explicit_allowlist(self): self.assertIn('Self.browsers.contains(request.bundle)',AX)
 def test_source_follows_live_foreground(self): self.assertIn('NSWorkspace.shared.frontmostApplication',body(APP,'private func refreshPinnedContext('))
 def test_reads_only_when_active(self): self.assertIn('guard active else { return }',body(MAC,'func update('))
 def test_no_eager_scan_in_init(self): self.assertNotIn('reader.scan',body(MAC,'init()'))
 def test_permission_checked_for_scan_and_press(self):
  self.assertIn('AXIsProcessTrusted()',body(AX,'func scan('));self.assertIn('AXIsProcessTrusted()',body(AX,'static func press('))
 def test_body_and_secure_fields_pruned(self):
  for f in ['private func webAreas(','private func sidebars(','private func snapshot(']:
   b=body(AX,f);self.assertIn('AXTextArea',b);self.assertIn('AXSecureTextField',b)
 def test_static_value_only_in_sidebar(self):
  self.assertEqual(AX.count('Self.string(node, "AXValue"'),1)
  self.assertIn('if title.isEmpty, d.role == "AXStaticText"',AX)
 def test_main_landmark_not_read_for_description(self):
  b=body(AX,'private func sidebars(');self.assertLess(b.index('subrole == "AXLandmarkMain"'),b.index('let d = descriptor'))
 def test_budget_and_message_timeouts(self):
  self.assertIn('Date().addingTimeInterval(1.2)',AX);self.assertIn('AXUIElementSetMessagingTimeout',AX);self.assertIn('maximumNodes',AX)
 def test_ambiguous_webroots_fail_closed(self): self.assertIn('guard roots.count <= 1',AX)
 def test_single_sidebar_required(self): self.assertIn('guard candidates.count == 1',AX)
 def test_limited_results_disabled(self): self.assertIn('if limited || inventory.limited',AX);self.assertIn('c.enabled = false',AX)
 def test_no_network_extension_credentials_clipboard(self):
  for text in [AX,MAC,CORE]:
   for forbidden in ['URLSession', 'NSPasteboard', 'NSAppleScript', 'CGEvent(', 'evaluateJavaScript', 'BrowserMailbox', 'UserDefaults', 'Data(contentsOf:', 'FileManager', 'Process()']:
    self.assertNotIn(forbidden,text)
 def test_no_actions_during_discovery(self): self.assertNotIn('PerformAction',body(AX,'func scan('))
 def test_exactly_one_press_no_retry(self):
  self.assertEqual(AX.count('AXUIElementPerformAction('),1)
  b=body(AX,'static func press(');self.assertNotIn('asyncAfter',b);self.assertNotIn('for ',b);self.assertNotIn('while ',b)
 def test_fresh_rescan_precedes_press(self):
  b=body(MAC,'private func navigate(');self.assertLess(b.index('reader.scan'),b.index('PinnedChatsAXReader.press'))
  self.assertLess(b.index('gate.consume'),b.index('PinnedChatsAXReader.press'))
 def test_native_pointer_and_focus_check(self):
  b=body(AX,'static func press(')
  for term in ['frontmostApplication', 'CFEqual(target, old)', 'CFEqual(fresh.sidebar, expected.sidebar)', 'AXFocusedWindow', 'documentURL == fresh.documentURL', 'AXPress']:
   self.assertIn(term,b)
 def test_stable_generation_keys(self): self.assertIn('pin-\\(generation.uuidString)-\\(chat.token)',MAC)
 def test_app_switch_is_explicit_not_discovery(self):
  self.assertNotIn('openApplication',AX);self.assertIn('openApplication',body(APP,'private func openPinnedAssistant('))
 def test_no_dispatch_from_timer(self): self.assertNotIn('navigate(',body(MAC,'func update('))
 def test_worker_serial_and_publication_cancelled(self):
  self.assertIn('DispatchQueue(label: "local.relaybar.pinned-chats"',MAC);self.assertIn('self.epoch == expectedEpoch',MAC)
 def test_status_never_claims_loaded(self): self.assertIn('Navigation requested for',MAC);self.assertIn('Check the app',MAC)
 def test_selfcheck_does_not_read_assistants(self):
  code=(ROOT/'Sources/Mac/PinnedChatsNativeChecks.swift').read_text()
  self.assertNotIn('reader.scan',code);self.assertNotIn('NSPasteboard',code);self.assertNotIn('presentOverlay',code)
 def test_metadata(self):
  p=plistlib.loads((ROOT/'Resources/Info.plist').read_bytes());self.assertEqual(p['CFBundleShortVersionString'],'0.9.1');self.assertEqual(p['CFBundleVersion'],'17')
 def test_build_includes_new_sources_unchanged(self): self.assertIn('"$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/Mac/*.swift',(ROOT/'Scripts/build.sh').read_text())
 def test_merged_routes_do_not_restore_extension(self):
  for token in ['browserMailbox', 'liveReceipt', 'dispatchBrowserAction', 'showSheetsSetup']:
   self.assertNotIn(token,APP)
  self.assertFalse((ROOT/'BrowserExtension').exists())
 def test_pins_cancel_native_actions_before_reading(self):
  self.assertIn('navigate(to: .pins)',body(APP,'@objc private func showPinnedChats()'))
  b=body(APP,'private func navigate(to destination:');self.assertLess(b.index('nativeMenus.cancelInteraction()'),b.index('reconcileNavigation()'))
 def test_stack_methods_survive_three_way_merge(self):
  for name in ['refreshStackUI()', 'showStackFromMenu()', 'toggleStackCollection()', 'reviewStack()']:
   self.assertIn('func '+name,APP)
 def test_heading_label_from_child_is_preserved(self):
  self.assertIn('["AXHeading", "AXDisclosureTriangle"].contains(d.role)',AX)
 def test_only_explicit_runtime_accessibility_preparation(self):
  self.assertEqual(AX.count('AXUIElementSetAttributeValue('),1)
  b=body(AX,'private func prepareAccessibility(')
  self.assertIn('AXUIElementIsAttributeSettable',b);self.assertIn('AXManualAccessibility',b)
 def test_worker_checks_foreground_before_and_after_scan(self):
  self.assertEqual(body(AX,'func scan(').count('isForeground(request.pid)'),2)
if __name__=='__main__':unittest.main(verbosity=2)

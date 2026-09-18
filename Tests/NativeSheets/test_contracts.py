"""Source contracts only. These do not typecheck AppKit or exercise a Mac."""
from pathlib import Path
import hashlib, plistlib, unittest
R=Path(__file__).resolve().parents[2]
A=(R/'Sources/Mac/AppMain.swift').read_text()
M=(R/'Sources/Mac/NativeAXSource.swift').read_text()
C=(R/'Sources/Mac/NativeMenuController.swift').read_text()
E=(R/'Sources/Core/NativeMenus.swift').read_text()
class NativeContracts(unittest.TestCase):
 def test_no_extension_or_spreadsheet_setup_shipped(self):
  for p in ['BrowserExtension','AppsScript','Set_Up_Sheets.command','Sources/Mac/BrowserNativeHost.swift']:
   self.assertFalse((R/p).exists(),p)
 def test_no_live_mailbox_routing(self):
  for token in ['browserMailbox','liveReceipt','dispatchBrowserAction','showSheetsSetup']:
   self.assertNotIn(token,A)
 def test_chromium_uses_one_verified_pointer_click_without_keys_or_javascript(self):
  for token in ['CGWarpMouseCursorPosition','NSAppleScript','osascript','evaluateJavaScript','URLSession','Process(','keyDown','keyUp']:
   self.assertNotIn(token,M+C+E)
  block=M.split('func pointerClick(',1)[1].split('func perform(',1)[0]
  self.assertEqual(block.count('CGEvent(mouseEventSource:'),2)
  self.assertEqual(block.count('.post(tap: .cghidEventTap)'),2)
  self.assertIn('verifiedPointerBundles.contains(route.bundle)',E)
 def test_reads_have_no_value_or_selected_text_attribute(self):
  enum=E.split('public enum NativeAXAttribute',1)[1].split('public struct NativeRect',1)[0]
  for token in ['"AXValue"','AXSelectedText','AXAttributedString','AXSelectedRows','AXRows']:
   self.assertNotIn(token,enum)
 def test_read_budget_and_per_call_timeout(self):
  for token in ['NativeReadBudget(now: now)', 'count <= NativeReadBudget.maximumChildren', 'AXUIElementSetMessagingTimeout']:
   self.assertIn(token,M)
  for token in ['seconds: Double = 0.85', 'maximumQueries = 5000', 'maximumChildren = 4096', 'maximumMenuNodes = 1600', 'childPageSize = 64']:
   self.assertIn(token,E)
 def test_cancel_token_checked_by_native_perform(self):
  action=M.split('func perform(',1)[1].split('/// Ask',1)[0]
  self.assertIn('take(), trusted',action)
  self.assertEqual(action.count('AXUIElementPerformAction('),1)
 def test_no_persisted_browsing_or_cell_cache(self):
  for token in ['FileManager','UserDefaults','write(to:','NSPasteboard','URLSession']:
   self.assertNotIn(token,M+C+E)
 def test_snapshot_does_not_contain_document_title(self):
  block=E.split('public struct NativeMenuSnapshot',1)[1].split('public enum NativeDispatchResult',1)[0]
  self.assertNotIn('title:',block)
 def test_native_detection_requires_explicit_global_consent_and_overlay(self):
  self.assertIn('enabled: appAwareEnabled && nativeMenusEnabled && overlayEnabled',A)
  self.assertIn('UserDefaults.standard.bool(forKey: "nativeMenus.enabled")',A)
  self.assertIn('private var overlayEnabled = false',A)
 def test_no_permission_bypass(self):
  for token in ['tccutil','TCC.db','csrutil','spctl --master-disable','defaults write com.google']:
   self.assertNotIn(token,A+M+(R/'Install.command').read_text())
 def test_screenshot_and_hide_cancel_native_interactions(self):
  self.assertIn('if didAdd { self.nativeMenus.cancelInteraction() }',A)
  block=A.split('@objc private func togglePersistentShellPause() {',1)[1].split('@objc private func',1)[0]
  self.assertIn('nativeMenus.clear()',block)
 def test_inline_confirmation_does_not_open_a_panel(self):
  block=A.split('if let pending = nativeMenus.pendingLabel',1)[1].split('if liveProfile == "sheets"',1)[0]
  self.assertNotIn('showPanel',block); self.assertIn('nativeMenus.confirm(expectedRevision: rev)',block)
 def test_retired_buttons_have_revision_keys(self):
  self.assertIn('key: "native-\\(rev)-\\(index)"',A)
  self.assertIn('expectedRevision == revision',C)
 def test_controller_callbacks_rebuild_native_bars(self):
  block=A.split('nativeMenus.onChange =',1)[1].split('nativeMenus.onStatus',1)[0]
  self.assertIn('rebuildBars()',block); self.assertIn('updateOverlay(',block)
 def test_version(self):
  d=plistlib.loads((R/'Resources/Info.plist').read_bytes())
  self.assertEqual(d['CFBundleShortVersionString'],'0.9.1'); self.assertEqual(d['CFBundleVersion'],'17')
 def test_native_report_does_not_include_url_or_labels(self):
  block=C.split('var connectionReport:',1)[1]
  self.assertNotIn('.url',block); self.assertNotIn('.label',block); self.assertIn('nodesVisited',block); self.assertIn('Last menu expansion:',block); self.assertIn('Menu Cascade + Lean Scan + Verified Click',block)
 def test_native_buttons_cannot_double_cancel_executing_request(self):
  self.assertIn('guard gate.executing == nil, expectedRevision',C)
  self.assertIn('guard gate.executing == nil else { return }',C)
 def test_only_optin_browser_accessibility_tree_writes(self):
  self.assertEqual(M.count('AXUIElementSetAttributeValue('),1)
  self.assertIn('["AXManualAccessibility", "AXEnhancedUserInterface"]',M)
  self.assertIn('AXUIElementIsAttributeSettable',M)
if __name__=='__main__': unittest.main(verbosity=2)

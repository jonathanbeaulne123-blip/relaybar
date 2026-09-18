#!/usr/bin/env python3
import hashlib, plistlib, re, unittest
from pathlib import Path
R=Path(__file__).resolve().parents[2]
A=(R/'Sources/Mac/AppMain.swift').read_text()
N=(R/'Sources/Core/NativeMenus.swift').read_text()
C=(R/'Sources/Mac/NativeMenuController.swift').read_text()
I=(R/'Install.command').read_text()
class UnifiedProduct(unittest.TestCase):
 def test_release(self):
  p=plistlib.loads((R/'Resources/Info.plist').read_bytes()); self.assertEqual((p['CFBundleShortVersionString'],p['CFBundleVersion']),('0.9.1','17'))
 def test_all_feature_engines_present(self):
  for f in ['Sources/Core/ButtonHierarchy.swift','Sources/Core/ContextStack.swift','Sources/Core/PinnedChats.swift','Sources/Core/ScreenshotPresentation.swift','Sources/Core/ScreenshotShelf.swift','Sources/Core/NativeMenus.swift']:
   self.assertTrue((R/f).is_file(),f)
 def test_no_extension_or_apps_script_runtime(self):
  self.assertFalse((R/'BrowserExtension').exists()); self.assertFalse((R/'AppsScript').exists())
  self.assertIn('no browser extension is required',A)
 def test_sheets_has_lean_scan_and_menu_cascade(self):
  for token in ['expandingMenu: Bool = false','role == "AXList"','strongOpenItem','control.isMenu ? source.flag(control.node, .enabled) != false']:
   self.assertIn(token,N)
  for token in ['menuExpansionUntil','Last menu expansion:','Menu Cascade + Lean Scan + Verified Click']:
   self.assertIn(token,C)
 def test_chromium_sheet_dispatch_is_verified_pointer_click(self):
  self.assertIn('verifiedPointerBundles.contains(route.bundle)',N)
  self.assertIn('func pointerClick(x: Double, y: Double)',(R/'Sources/Mac/NativeAXSource.swift').read_text())
 def test_app_aware_sheet_transition_is_real(self):
  self.assertIn('navigation.open(.appControls)',A); self.assertIn('nativeRouteChanged',A)
  self.assertIn('navigation.page != .screenshots',A)
 def test_screenshot_auto_open_preserved(self):
  self.assertIn('screenshotPresentation.screenshotAdded()',A); self.assertIn('scheduleScreenshotRecovery(ticket:',A)
 def test_context_stack_wired(self):
  self.assertIn('ContextStackController',A); self.assertIn('toggleStackCollection()',A); self.assertIn('contextStack?.slots(',A)
 def test_pins_wired(self):
  self.assertIn('PinnedChatsController',A); self.assertIn('showPinnedChats()',A); self.assertIn('pinnedChats?.slots(',A)
 def test_button_families_are_root_layout(self):
  self.assertIn('private func familySlots()',A); self.assertIn('RelayHierarchy.items(on:',A)
 def test_permission_recovery_shipped(self):
  self.assertTrue((R/'Fix_Access.command').is_file()); self.assertIn("0.9.1:17",(R/'Fix_Access.command').read_text())
 def test_installer_accepts_current_working_lineages(self):
  for token in ['0.5.2:12','0.7.0:11','0.8.0:13|0.8.1:14|0.8.2:15','0.9.0:*','0.9.1:*']:
   self.assertIn(token,I)
 def test_current_runtime_source_has_no_extension_entrypoint(self):
  self.assertIn('--browser-native',A); self.assertIn('exit(2)',A)
if __name__=='__main__': unittest.main(verbosity=2)

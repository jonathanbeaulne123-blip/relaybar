"""Hierarchy integration contracts. Source checks, NOT native AppKit execution."""
from pathlib import Path
import hashlib, json, plistlib, unittest
R=Path(__file__).resolve().parents[2]
A=(R/'Sources/Mac/AppMain.swift').read_text();C=(R/'Sources/Core/ButtonHierarchy.swift').read_text()
def body(signature):
 i=A.index(signature);i=A.index('{',i);n=0
 for j in range(i,len(A)):
  n+=(A[j]=='{')-(A[j]=='}')
  if n==0:return A[i:j+1]
 raise ValueError(signature)
class FamilyWiring(unittest.TestCase):
 def test_bar_has_one_catalog_adapter(self):self.assertIn('let slots = familySlots()',body('private func rebuildBars()'))
 def test_menu_uses_shared_catalog(self):self.assertIn('RelayHierarchy.items(on: page)',body('private func familyMenu('))
 def test_all_five_families_in_main_menu(self):
  b=body('private func buildMenu()')
  self.assertIn('RelayHierarchy.items(on: .home)',b);self.assertIn('familyMenu(page)',b)
  for name in ['.prompting','.context','.chats','.workspace','.settings']:self.assertIn(name,C)
 def test_folders_do_not_run_actions(self):
  b=body('private func groupSlot(');self.assertIn('navigate(to: page)',b)
  for bad in ['runFamilyCommand(', 'performAction(', 'copyDraft(', 'toggleStackCollection(']:self.assertNotIn(bad,b)
 def test_prompt_actions_use_original_composer(self):self.assertIn('case .prompt(let action): performAction(action)',A)
 def test_successful_compose_opens_draft(self):self.assertIn('composeSelected()',body('private func performAction('));self.assertIn('navigate(to: .draft)',body('private func composeSelected('))
 def test_every_leaf_guarded_by_generation(self):
  b=body('private func familySlots()');self.assertIn('self.navigation.accepts(ticket)',b);self.assertIn('item.isEnabled',b)
 def test_native_confirmation_back_prioritizes_cancel(self):
  b=body('private func navigateBack()');self.assertIn('RelayHierarchy.nativeBack(',b);self.assertIn('nativeMenus.cancelConfirmation()',b);self.assertIn('nativeMenus.showMenus()',b)
 def test_navigation_cancels_pending_native_interaction(self):
  b=body('private func navigate(to destination:');self.assertLess(b.index('nativeMenus.cancelInteraction()'),b.index('navigation.open(destination)'))
 def test_screenshot_interrupt_remembers_nav_path(self):self.assertIn('navigation.screenshotArrived(autoOpen: true)',body('screenshotShelf?.onChange ='))
 def test_native_refresh_does_not_reset_ordinary_groups(self):
  b=body('private func refreshAppContext()');self.assertIn('navigation.externalContextChanged(appAware: true)',b);self.assertNotIn('navigate(to: .home)',b)
 def test_sheet_context_automatically_enters_app_controls(self):
  b=body('private func refreshAppContext()');self.assertIn('liveProfile == "sheets"',b);self.assertIn('navigation.open(.appControls)',b);self.assertIn('nativeRouteChanged',b);self.assertIn('navigation.page != .screenshots',b);self.assertIn('navigation.open(.home)',b)
 def test_dynamic_data_reuses_original_controllers(self):
  b=body('private func familySlots()')
  for term in ['pinnedChats?.slots(', 'contextStack?.slots(', 'screenshotSlots()', 'appAwareSlots(fallback:'] :self.assertIn(term,b)
 def test_escape_back_then_hide(self):
  b=body('panel.onEscape =');self.assertIn('navigation.page == .home',b);self.assertIn('navigateBack()',b);self.assertIn('hidePanel()',b)
 def test_breadcrumb_is_on_native_panel(self):self.assertIn('full(familyPathLabel)',A);self.assertIn('navigation.page.breadcrumb',A)
 def test_clear_session_requires_second_button(self):self.assertIn('alertSecondButtonReturn',body('private func confirmClearSession()'))
 def test_retains_collection_pause_on_hide(self):self.assertIn('contextStack?.pause(',body('@objc private func togglePersistentShellPause()'))
 def test_selftest_uses_named_clipboard_not_general(self):
  b=body('func runButtonFamiliesSelfTest()');self.assertIn('NSPasteboard(name:',b);self.assertNotIn('NSPasteboard.general',b);self.assertNotIn('refreshPinnedContext(',b);self.assertNotIn('presentOverlay',b)
 def test_release_metadata(self):
  p=plistlib.loads((R/'Resources/Info.plist').read_bytes());self.assertEqual((p['CFBundleShortVersionString'],p['CFBundleVersion']),('0.9.1','17'))
 def test_no_extension_resurrection(self):
  self.assertFalse((R/'BrowserExtension').exists());self.assertFalse((R/'Sources/Mac/BrowserNativeHost.swift').exists())
 def test_suggestions_marked_not_moved(self):self.assertIn('title = "★ " + title',body('private func commandSlot('));self.assertIn('.prompt(.nextSlice)',C)
if __name__=='__main__':unittest.main(verbosity=2)

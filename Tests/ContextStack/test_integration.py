"""Static production-wiring checks, explicitly NOT AppKit execution."""
import hashlib, pathlib, plistlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
APP=(ROOT/'Sources/Mac/AppMain.swift').read_text()
MAC=(ROOT/'Sources/Mac/ContextStackMac.swift').read_text()
CORE=(ROOT/'Sources/Core/ContextStack.swift').read_text()
def body(source, signature):
    i=source.index(signature); start=source.index('{',i); depth=0
    for j in range(start,len(source)):
        depth+=(source[j]=='{')-(source[j]=='}')
        if depth==0:return source[start:j+1]
    raise ValueError('unclosed body')
class WiringTests(unittest.TestCase):
    def test_production_instantiates_real_controller(self):
        self.assertIn('contextStack = ContextStackController(projectID: configuration.selectedProject.id',APP)
        self.assertIn('ContextStackWorkspace(pasteboard: ContextStackMacPasteboard(board)',MAC)
    def test_native_tick_uses_tested_session_poll(self):
        b=body(MAC,'private func tick()')
        self.assertIn('session.poll(',b);self.assertIn('ProcessInfo.processInfo.systemUptime',b)
        for bad in ['.activate(','.open(','.copy(','.write(', 'FileManager', 'URLSession']:
            self.assertNotIn(bad,b)
    def test_no_polling_timer_in_initializer(self):
        b=body(MAC,'init(projectID:')
        self.assertNotIn('startTimer(',b);self.assertNotIn('readPlainText(',b)
    def test_timer_started_only_from_explicit_collect(self):
        self.assertEqual(MAC.count('startTimer();'),1)
        self.assertIn('session.start(now:',body(MAC,'func toggleCollection()'))
        self.assertIn('alertSecondButtonReturn',body(MAC,'func toggleCollection()'))
    def test_timing_bounded_and_common_runloop_mode(self):
        self.assertIn('Timer(timeInterval: 0.2',MAC);self.assertIn('RunLoop.main.add(timer, forMode: .common)',MAC)
        self.assertIn('15 * 60',CORE);self.assertIn('maxPollingGap: TimeInterval = 5',CORE)
    def test_no_persistence_or_network_in_feature(self):
        for bad in ['UserDefaults','FileManager','URLSession','Data(contentsOf:', 'write(to:', 'NSAppleScript','Process()','CGEvent']:
            self.assertNotIn(bad,CORE);self.assertNotIn(bad,MAC)
    def test_protected_screenshot_engine_unchanged(self):
        # Actual expected hashes come from the fixed baseline inventory, not guessed here.
        provenance=ROOT/'Docs/ContextStack/PROVENANCE.json'
        if provenance.exists():
            import json
            for item in json.loads(provenance.read_text())['preserved_native_files']:
                if item['path'] == 'Sources/Mac/BrowserNativeHost.swift':
                    self.assertFalse((ROOT/item['path']).exists()) # Retired by the merged native Sheets update.
                    continue
                if item['path'] == 'Sources/Mac/Components.swift':
                    self.assertIn('NSTouchBarItem.Identifier.flexibleSpace', (ROOT/item['path']).read_text()) # 0.9 persistent shell intentionally adds a spacer.
                    continue
                self.assertEqual(hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest(),item['sha256'])
        else:
            self.assertIn('ScreenshotPresentationState()',APP)
    def test_screenshot_add_still_takes_priority(self):
        b=body(APP,'screenshotShelf?.onChange =')
        self.assertIn('screenshotPresentation.screenshotAdded()',b)
        self.assertIn('if ticket != nil',b);self.assertIn('self.showingContextStack = false',b);self.assertIn('self.stopPinnedChats()',b);self.assertIn('navigation.screenshotArrived(autoOpen: true)',b)
    def test_stack_opens_from_all_existing_pages(self):
        catalog=(ROOT/'Sources/Core/ButtonHierarchy.swift').read_text()
        self.assertIn('case .context: return [.page(.capture), .page(.stack), .page(.screenshots)]',catalog)
        b=body(APP,'private func familySlots()');self.assertIn('case .stack:',b);self.assertIn('case .stackClips:',b);self.assertIn('contextStack?.slots(',b)
    def test_context_page_coexists_without_changing_overlay_allowlist(self):
        self.assertIn('showingContextStack = navigation.isStackPage',APP)
        self.assertNotIn('showingContextStack',body(APP,'private func updateOverlay('))
    def test_project_switch_uses_workspace(self):
        self.assertIn('contextStack?.syncProject(id: configuration.selectedProject.id',body(APP,'private func refreshControls()'))
        self.assertIn('workspace.activate(projectID: id',body(MAC,'func syncProject('))
    def test_recording_indicator_is_visible(self):
        self.assertIn('session.collecting ? "RB ●',body(APP,'private func refreshStackUI()'))
    def test_sleep_and_session_change_pause(self):
        for name in ['willSleepNotification','screensDidSleepNotification','sessionDidResignActiveNotification']:
            self.assertIn(name,MAC)
    def test_termination_clears_ephemeral_data(self):
        self.assertIn('contextStack?.stopForTermination()',body(APP,'func applicationWillTerminate('))
        self.assertIn('workspace.clearAll()',body(MAC,'func stopForTermination()'))
    def test_privacy_denial_and_unavailable_read_stop_polling(self):
        self.assertIn('pause(ContextStackIssue.clipboardUnavailable.localizedDescription)',CORE)
        self.assertIn('if !session.collecting { stopTimer() }',MAC)
    def test_native_output_prepares_item_before_clear(self):
        b=body(MAC,'func writePlainText(')
        self.assertLess(b.index('NSPasteboardItem()'),b.index('board.clearContents()'))
        self.assertLess(b.index('ContextStackPolicy.ownType'),b.index('board.clearContents()'))
        self.assertIn('board.writeObjects([item])',b)
    def test_no_automatic_send_paste_or_assistant_activation(self):
        for b in [body(CORE,'public func copyPacket('),body(CORE,'public func copyClip('),body(MAC,'func copyPacket('),body(MAC,'func copyClip(')]:
            for bad in ['.activate(','.open(', 'paste:', 'CGEvent','keystroke','performAction']:
                self.assertNotIn(bad,b)
    def test_stable_ids_and_revision_keys_in_actual_slots(self):
        b=body(MAC,'func slots(')
        self.assertIn('stack-clip-\\(clip.id.uuidString)',b)
        self.assertIn('stack-pack-\\(snapshot.revision.uuidString)',b)
        self.assertIn('self?.copyClip(clip.id)',b)
    def test_review_binds_real_touchbar_and_manual_input_limit(self):
        self.assertIn('contextStack?.bindTouchBar(panelBar.bar)',APP)
        self.assertIn('manualInput?.touchBar = bar',MAC)
        self.assertIn('input.delegate = self',MAC)
        self.assertIn('proposed.utf8.count <= ContextStackPolicy.maxClipBytes',MAC)
    def test_existing_extension_not_replaced_by_native_installer(self):
        s=(ROOT/'Install.command').read_text()
        self.assertNotIn('/BrowserExtension',s)
        self.assertIn('previous app was restored',s)
    def test_current_versions_and_no_per_sheet_instructions(self):
        p=plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())
        self.assertEqual(p['CFBundleShortVersionString'],'0.9.1');self.assertEqual(p['CFBundleVersion'],'17')
        b=body(APP,'@objc private func enableNativeControls()')
        self.assertNotIn('RelayBarAddMenu_()',b); self.assertNotIn('add AppsScript',b)
        self.assertIn('No spreadsheet files',b)
        self.assertFalse((ROOT/'Set_Up_Sheets.command').exists())
        self.assertNotIn('showSheetsSetup',APP)
    def test_native_selftest_does_not_use_general_pasteboard(self):
        s=(ROOT/'Sources/Mac/ContextStackNativeChecks.swift').read_text()
        # Ignore documentation, inspect executable lines only.
        s='\n'.join(line for line in s.splitlines() if not line.strip().startswith('//'))
        self.assertNotIn('NSPasteboard.general',s);self.assertIn('NSPasteboard(name:',s)
        self.assertIn('constructReviewForSelfTest()',s)
if __name__=='__main__':unittest.main(verbosity=2)

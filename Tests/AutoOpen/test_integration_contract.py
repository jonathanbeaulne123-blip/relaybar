"""Static production-wiring checks, NOT a substitute for native macOS execution.
0.5 updates release metadata and adds an explicit native-onboarding enable path.
Screenshot behavior assertions and all foundation hash pins are preserved.
"""
import hashlib
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = (ROOT / 'Sources/Mac/AppMain.swift').read_text()
COMPONENTS = (ROOT / 'Sources/Mac/Components.swift').read_text()

def body(source, signature):
    start = source.index(signature)
    start = source.index('{', start)
    depth = 0
    for end in range(start, len(source)):
        depth += (source[end] == '{') - (source[end] == '}')
        if depth == 0:
            return source[start:end + 1]
    raise ValueError('Unbalanced function body')

class IntegrationContractTests(unittest.TestCase):
    def test_only_successful_image_addition_triggers_auto_open(self):
        callback = body(APP, 'screenshotShelf?.onChange =')
        self.assertIn('didAdd ? self.screenshotPresentation.screenshotAdded() : nil', callback)
        self.assertIn('if let ticket = ticket', callback)
    def test_capture_callback_does_not_steal_focus_or_touch_clipboard(self):
        callback = body(APP, 'screenshotShelf?.onChange =')
        for forbidden in ['showPanel(', '.activate(', '.open(', '.copy(', 'NSPasteboard', 'performAction(']:
            self.assertNotIn(forbidden, callback)
    def test_retries_are_bounded_by_tested_policy(self):
        retry = body(APP, 'private func scheduleScreenshotRecovery(')
        self.assertIn('for delay in ScreenshotPresentationState.recoveryDelays', retry)
        self.assertNotIn('Timer(', retry)
        self.assertNotIn('while ', retry)
    def test_retries_recheck_live_app_and_enabled_ticket(self):
        retry = body(APP, 'private func scheduleScreenshotRecovery(')
        self.assertIn('self.overlayEnabled', retry)
        self.assertIn('requestRecovery(ticket: ticket)', retry)
        self.assertIn('NSWorkspace.shared.frontmostApplication', retry)
        for forbidden in ['showPanel(', '.activate(', 'NSPasteboard']:
            self.assertNotIn(forbidden, retry)
    def test_reopen_dismisses_before_present(self):
        route = body(APP, 'private func updateOverlay(')
        self.assertLess(route.index('overlayAction('), route.index('bridge.presentOverlay('))
        self.assertLess(route.index('case .reopen:'), route.index('bridge.presentOverlay('))
        self.assertIn('bridge.dismissOverlay()', route[route.index('case .reopen:'):route.index('case .present:')])
    def test_persistent_shell_is_default_but_mac_mode_is_explicit(self):
        self.assertIn('PersistentShellState(enabled: UserDefaults.standard.object(forKey: "persistentShell.enabled") as? Bool ?? true)', APP)
        self.assertIn('overlayEnabled = shellState.relayVisible', APP)
        self.assertIn('shellState.enterMacMode()', body(APP, 'private func enterMacTouchBarMode('))
        self.assertIn('overlayEnabled = false', body(APP, 'private func enterMacTouchBarMode('))
        self.assertIn('returnToRelayBar(showPanel: false)', body(APP, '@objc private func toggleOverlay('))
    def test_working_bridge_is_byte_identical(self):
        pins = {'Sources/Bridge/NativeBridge.h': '4808436e6e1133e0dcd541ddbdd257852eaba5e0ffcc30f084202aa933c6c00f',
                'Sources/Bridge/NativeBridge.m': '2f3bd574b40cd38c02fbc4a4d85207652791cdac9149a480e821639270e138bd'}
        for path, sha in pins.items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), sha)
    def test_build_and_compiler_workaround_are_byte_identical(self):
        pins = {'Scripts/toolchain.sh': 'b91541971c6a04d84133ab8b9778ace9e8a085809246e42b6b792bc252686dda',
                'Scripts/build.sh': 'ce6261d26d6f2d2e54598a2371e120185f377b68c6e671e72548400cc54bf3c8'}
        for path, sha in pins.items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), sha)
    def test_watcher_cache_and_copy_engine_are_byte_identical(self):
        pins = {'Sources/Mac/ScreenshotShelfMac.swift': '3abcb5ccf5a048469a285d1d43311a3fad9c74f7058fdac2b62b7db33b7354ee',
                'Sources/Core/ScreenshotShelf.swift': '0b17283425de93c7f5ca0150885bf24d393c4104b580689a1a60c314dcb7c6c2'}
        for path, sha in pins.items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), sha)
    def test_manual_choices_cancel_or_replace_pending_reveal(self):
        self.assertIn('navigate(to: .home)', body(APP, 'private func showToolsPage('))
        self.assertIn('screenshotPresentation.showTools()', body(APP, 'private func reconcileNavigation('))
        self.assertIn('screenshotPresentation.cancelRecovery()', body(APP, 'private func copyScreenshot('))
        self.assertIn('screenshotPresentation.overlayDisabled()', body(APP, '@objc private func togglePersistentShellPause('))
    def test_fresh_bar_is_rebound_to_native_responders(self):
        self.assertIn('let replacement = NSTouchBar()', COMPONENTS)
        self.assertIn('button.isEnabled = false', COMPONENTS)
        self.assertIn('guard touchBar === bar else { return nil }', COMPONENTS)
        rebuild = body(APP, 'private func rebuildBars(')
        for responder in ['panel?', 'referenceView?', 'draftView?']:
            self.assertIn(responder + '.touchBar = panelBar.bar', rebuild)
    def test_version_and_auto_open_default(self):
        info = plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleShortVersionString'], '1.0.0')
        self.assertEqual(info['CFBundleVersion'], '20')
        self.assertEqual(info['CFBundleIdentifier'], 'local.relaybar')
        self.assertIn('UserDefaults.standard.object(forKey: autoOpenKey) as? Bool ?? true', APP)
        self.assertIn('case .autoScreenshots:', APP)
        self.assertIn('screenshotAutoOpenMenuItem = control', APP)
    def test_persistent_overlay_routes_all_external_apps_without_reclaiming_mac_mode(self):
        route = body(APP, 'private func updateOverlay(')
        self.assertIn('shellState.shouldPresent(frontmostIsRelay: ownApp($0), captureHelper: isCaptureHelper($0))', route)
        self.assertIn('shellState.relayVisible', route)
        self.assertNotIn('let browsers =', route)
    def test_queued_activation_uses_current_app(self):
        activation = body(APP, 'private func activeApplicationChanged(')
        self.assertIn('guard let app = NSWorkspace.shared.frontmostApplication else', activation)

if __name__ == '__main__':
    unittest.main(verbosity=2)

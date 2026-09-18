import pathlib, plistlib, re, unittest

R = pathlib.Path(__file__).resolve().parents[2]
APP = (R/'Sources/Mac/AppMain.swift').read_text()
COMP = (R/'Sources/Mac/Components.swift').read_text()
SHELLMAC = (R/'Sources/Mac/PersistentShellMac.swift').read_text()
INSTALL = (R/'Install.command').read_text()
UNINSTALL = (R/'Uninstall.command').read_text()
NATIVE = (R/'Sources/Mac/NativeMenuController.swift').read_text()
AX = (R/'Sources/Mac/NativeAXSource.swift').read_text()

class PersistentShellContracts(unittest.TestCase):
    def test_version(self):
        p = plistlib.loads((R/'Resources/Info.plist').read_bytes())
        self.assertEqual((p['CFBundleShortVersionString'], p['CFBundleVersion']), ('1.0.0','20'))
        self.assertIn('"version": "1.0.0"', APP)
        self.assertIn('RelayBar 0.9.1 · Native Sheets engine 0.5.4 · Menu Cascade + Lean Scan + Verified Click + Persistent Shell', NATIVE)

    def test_return_path_does_not_shadow_show_panel_method(self):
        self.assertIn('private func returnToRelayBar(showPanel shouldShowPanel: Bool)', APP)
        self.assertIn('if shouldShowPanel { showPanel() }', APP)
        self.assertNotIn('if showPanel { showPanel() }', APP)

    def test_shell_is_default_and_decorates_contextual_slots(self):
        self.assertIn('PersistentShellState(enabled: UserDefaults.standard.object(forKey: "persistentShell.enabled") as? Bool ?? true)', APP)
        self.assertIn('overlayEnabled = shellState.relayVisible', APP)
        self.assertIn('return persistentShellSlots(contextual: contextual)', APP)
        self.assertNotIn('family-hide', APP)

    def test_right_side_order_and_mac_escape(self):
        block = APP[APP.index('private func persistentShellSlots'):APP.index('private func shellAppURL')]
        positions = [block.index('shellAppSlot(.chrome)'), block.index('shellAppSlot(.claude)'), block.index('shellAppSlot(.chatgpt)'), block.index('key: "shell-mac"')]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('TouchBarDriver.flexibleSpaceKey', block)
        self.assertIn('enterMacTouchBarMode()', block)
        self.assertIn('title: ""', block)

    def test_touchbar_supports_real_flexible_space(self):
        self.assertIn('NSTouchBarItem.Identifier.flexibleSpace', COMP)
        self.assertIn('if identifier == .flexibleSpace { return nil }', COMP)

    def test_mac_mode_does_not_reclaim_on_app_switch(self):
        enter = APP[APP.index('private func enterMacTouchBarMode'):APP.index('private func returnToRelayBar')]
        self.assertIn('shellState.enterMacMode()', enter)
        self.assertIn('overlayEnabled = false', enter)
        self.assertIn('bridge.dismissOverlay()', enter)
        changed = APP[APP.index('private func activeApplicationChanged'):APP.index('private func updateOverlay')]
        self.assertNotIn('returnToRelayBar', changed)
        update = APP[APP.index('private func updateOverlay'):APP.index('private func showPanel')]
        self.assertIn('shellState.shouldPresent', update)
        self.assertIn('shellState.relayVisible', update)

    def test_app_buttons_are_explicit_user_actions(self):
        for app in ['chrome','claude','chatgpt']:
            self.assertIn(f'shellAppSlot(.{app})', APP)
        self.assertIn('self?.activateShellApp(app)', APP)
        activation = APP[APP.index('private func activateShellApp'):APP.index('private func groupSlot')]
        self.assertIn('running.activate', activation)
        self.assertIn('NSWorkspace.shared.openApplication', activation)
        self.assertIn('isEnabled: installed', APP)
        changed = APP[APP.index('private func activeApplicationChanged'):APP.index('private func updateOverlay')]
        self.assertNotIn('activateShellApp', changed)

    def test_screenshot_page_uses_same_shell(self):
        self.assertIn('case .screenshots:', APP)
        self.assertIn('return persistentShellSlots(contextual: contextual)', APP)
        self.assertIn('navigation.screenshotArrived(autoOpen: true)', APP)

    def test_login_at_login_is_user_only_and_not_keepalive(self):
        self.assertIn('local.relaybar.login.plist', INSTALL)
        self.assertIn('<key>RunAtLoad</key><true/>', INSTALL)
        self.assertNotIn('<key>KeepAlive</key>', INSTALL)
        self.assertIn('/usr/bin/open', INSTALL)
        self.assertIn('local.relaybar.login.plist', UNINSTALL)
        self.assertIn('persistentShell.loginEnabled', APP)
        self.assertIn('RunAtLoad', SHELLMAC)
        self.assertNotIn('KeepAlive', SHELLMAC)

    def test_verified_sheets_click_is_retained(self):
        self.assertIn('verifiedPointerBundles', NATIVE)
        self.assertIn('pointerDispatch', NATIVE)
        self.assertIn('func pointerClick', AX)
        self.assertIn('CGEvent', AX)
        self.assertIn('leftMouseDown', AX)
        self.assertIn('leftMouseUp', AX)

    def test_no_extension_or_per_sheet_runtime_added(self):
        self.assertFalse((R/'BrowserExtension').exists())
        self.assertFalse((R/'AppsScript').exists())
        self.assertNotIn('chrome.runtime', APP)
        self.assertNotIn('google.script.run', APP)

if __name__ == '__main__': unittest.main()

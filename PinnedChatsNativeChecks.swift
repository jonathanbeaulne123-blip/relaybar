import Cocoa

/// Native component-construction check; intentionally no live AX scan, general
/// clipboard access, assistant activation or physical-overlay presentation.
@MainActor
enum PinnedChatsNativeChecks {
    static func run() -> Int32 {
        var failures = 0, checks = 0
        func check(_ condition: Bool, _ label: String) {
            checks += 1
            if condition { print("PASS: \(label)") } else { failures += 1; print("FAIL: \(label)") }
        }
        let controller = PinnedChatsController()
        var left = false, hidden = false
        let slots = controller.slots(back: { left = true }, hide: { hidden = true })
        check(slots.first?.key == "pins-tools", "Native Pins page begins with Tools")
        check(slots.contains { $0.key == "pins-help" }, "No synthetic conversation is presented as a real pin")
        check(slots.first { $0.key == "pins-prev" }?.isEnabled == false, "Empty previous page is disabled")
        check(slots.first { $0.key == "pins-next" }?.isEnabled == false, "Empty next page is disabled")
        check(slots.compactMap(\.width).reduce(0, +) < 610, "Fixed native item widths remain bounded")
        let driver = TouchBarDriver(); driver.update(slots)
        for slot in slots {
            let item = driver.touchBar(driver.bar, makeItemForIdentifier: NSTouchBarItem.Identifier("local.relaybar.\(slot.key)"))
            check(item is NSCustomTouchBarItem, "Native item constructed: \(slot.key)")
            if let button = (item as? NSCustomTouchBarItem)?.view as? NSButton {
                check(button.isEnabled == slot.isEnabled, "Enabled state matches: \(slot.key)")
            } else { check(false, "Expected native button: \(slot.key)") }
        }
        slots.first?.action(); check(left, "Tools callback is wired")
        slots.last?.action(); check(hidden, "Hide callback is wired")
        let previous = driver.bar
        driver.update([.init(key: "retired-test", title: "Test", help: "No external action", action: {})])
        check(previous !== driver.bar, "Structural change retires the native bar")
        check(driver.touchBar(previous, makeItemForIdentifier: NSTouchBarItem.Identifier("local.relaybar.pins-help")) == nil,
              "Retired controls cannot navigate")
        controller.stopForTermination()
        print("\(checks) native construction checks; \(failures) failures. Not a live assistant, Accessibility or hardware test.")
        return failures == 0 ? 0 : 1
    }
}

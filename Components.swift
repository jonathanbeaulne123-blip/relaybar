import Cocoa

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class RelayPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class ActionButton: NSButton {
    var handler: (() -> Void)?
    init(_ title: String, help: String? = nil, handler: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        self.handler = handler
        target = self
        action = #selector(run)
        bezelStyle = .rounded
        controlSize = .regular
        toolTip = help
        setContentHuggingPriority(.required, for: .horizontal)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
    @objc private func run() { handler?() }
}

@MainActor
final class TouchBarDriver: NSObject, NSTouchBarDelegate {
    struct Slot {
        var key: String
        var title: String
        var help: String
        var image: NSImage? = nil
        var isEnabled: Bool = true
        var width: CGFloat? = nil
        var customView: NSView? = nil
        var action: () -> Void
    }
    static let flexibleSpaceKey = "__relaybar_flexible_space__"

    private(set) var bar = NSTouchBar()
    private var slots: [Slot] = []
    private var buttons: [String: NSButton] = [:]
    private var widths: [String: NSLayoutConstraint] = [:]

    override init() {
        super.init()
        bar.delegate = self
    }
    func update(_ slots: [Slot]) {
        let identifiers = slots.map { slot in
            slot.key == Self.flexibleSpaceKey ? NSTouchBarItem.Identifier.flexibleSpace : NSTouchBarItem.Identifier("local.relaybar.\(slot.key)")
        }
        if bar.defaultItemIdentifiers != identifiers {
            // A page change or a new screenshot is a structural change. Start a
            // fresh bar rather than relying on cached items for retired keys.
            // Retired controls are disabled so a delayed touch cannot copy a
            // different image after the newest-first shelf has moved.
            for button in buttons.values { button.image = nil; button.isEnabled = false }
            for constraint in widths.values { constraint.isActive = false }
            buttons.removeAll(); widths.removeAll()
            let replacement = NSTouchBar()
            replacement.delegate = self
            bar = replacement
            self.slots = slots
            replacement.defaultItemIdentifiers = identifiers
        } else {
            // Copy checkmarks and text changes update in place without flicker.
            self.slots = slots
            for slot in slots {
                if let button = buttons[slot.key] { configure(button, slot: slot) }
            }
        }
    }
    private func configure(_ button: NSButton, slot: Slot) {
        button.title = slot.title; button.toolTip = slot.help; button.isEnabled = slot.isEnabled
        button.image = slot.image; button.imagePosition = slot.image == nil ? .noImage : .imageLeft
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel(slot.help)
        if let width = slot.width {
            if let existing = widths[slot.key], existing.firstItem as? NSButton === button {
                existing.constant = width
            } else {
                widths[slot.key]?.isActive = false
                let constraint = button.widthAnchor.constraint(equalToConstant: width)
                constraint.priority = .defaultHigh; constraint.isActive = true; widths[slot.key] = constraint
            }
        }
        if slot.key.contains("browser-tab-") {
            let isSelected = slot.title.contains("●")
            if isSelected {
                button.bezelColor = NSColor(calibratedRed: 0.23, green: 0.25, blue: 0.28, alpha: 1.0)
                button.font = .systemFont(ofSize: 11, weight: .semibold)
            } else {
                button.bezelColor = NSColor(calibratedWhite: 0.14, alpha: 0.85)
                button.font = .systemFont(ofSize: 11, weight: .regular)
            }
        }
    }
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard touchBar === bar else { return nil }
        if identifier == .flexibleSpace { return nil }
        let key = identifier.rawValue.replacingOccurrences(of: "local.relaybar.", with: "")
        guard let slot = slots.first(where: { $0.key == key }) else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        if let custom = slot.customView {
            item.view = custom
            item.customizationLabel = slot.help
            return item
        }
        let button = ActionButton(slot.title, help: slot.help) { [weak self] in
            self?.slots.first(where: { $0.key == key })?.action()
        }
        configure(button, slot: slot)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        if key == "target" { button.bezelColor = .systemIndigo }
        if key == "capture" { button.bezelColor = .systemTeal }
        button.setAccessibilityLabel(slot.help)
        item.view = button
        item.customizationLabel = slot.help
        buttons[key] = button
        return item
    }
}

@MainActor
final class ScrollableTabsView: NSScrollView {
    private let stackView = NSStackView()
    private var dragStartX: CGFloat = 0
    private var dragStartOriginX: CGFloat = 0

    init(tabs: [BrowserTab], bundle: String, width: CGFloat = 340, onActivate: @escaping (Int, String) -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        self.hasHorizontalScroller = false
        self.hasVerticalScroller = false
        self.horizontalScrollElasticity = .allowed
        self.verticalScrollElasticity = .none
        self.drawsBackground = false
        self.borderType = .noBorder
        // The Touch Bar digitizer delivers one-finger drags as direct touches.
        // Opting in lets the strip follow a finger slide instead of paging with
        // dedicated previous/next buttons.
        self.allowedTouchTypes = [.direct]

        self.translatesAutoresizingMaskIntoConstraints = false
        self.widthAnchor.constraint(equalToConstant: width).isActive = true
        self.heightAnchor.constraint(equalToConstant: 30).isActive = true

        stackView.orientation = .horizontal
        stackView.spacing = 4
        stackView.alignment = .centerY
        stackView.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

        var selectedButton: NSButton?

        for tab in tabs {
            let isCurrent = tab.isSelected
            let title = (isCurrent ? "● " : "") + tab.cleanTitle
            let icon = FaviconProvider.shared.favicon(for: tab.url, domain: tab.domain)

            let btn = ActionButton(title, help: tab.title.isEmpty ? tab.url : tab.title) {
                onActivate(tab.index, bundle)
            }
            btn.image = icon
            btn.imagePosition = .imageLeft
            btn.imageScaling = .scaleProportionallyDown
            btn.font = .systemFont(ofSize: 11, weight: isCurrent ? .semibold : .regular)

            // As small as practical: the width tracks the visible characters so
            // more tabs fit at once, while the selected tab stays readable.
            let chars = CGFloat(min(tab.cleanTitle.count, 9))
            let tabWidth = min(66, max(36, chars * 5.6 + (isCurrent ? 30 : 24)))
            btn.widthAnchor.constraint(equalToConstant: tabWidth).isActive = true

            if isCurrent {
                btn.bezelColor = NSColor(calibratedRed: 0.23, green: 0.25, blue: 0.28, alpha: 1.0)
                selectedButton = btn
            } else {
                btn.bezelColor = NSColor(calibratedWhite: 0.14, alpha: 0.85)
            }
            stackView.addArrangedSubview(btn)
        }

        self.documentView = stackView

        // Auto-scroll the selected tab into view once the strip has a frame.
        if let sel = selectedButton {
            DispatchQueue.main.async { [weak self] in self?.scrollToVisibleTab(sel) }
        }
    }

    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func layout() {
        super.layout()
        // NSScrollView never sizes a document view for us. Without an explicit
        // frame the strip collapses to zero and no tabs are drawn at all.
        let natural = stackView.fittingSize
        let height = max(1, bounds.height)
        let docWidth = max(bounds.width, natural.width)
        let target = NSRect(x: 0, y: 0, width: docWidth, height: height)
        if stackView.frame != target { stackView.frame = target }
        clampScrollOrigin()
    }

    // MARK: - Finger and wheel sliding

    override func touchesBegan(with event: NSEvent) {
        guard let touch = event.touches(matching: .began, in: self).first else { return }
        dragStartX = touch.normalizedPosition.x
        dragStartOriginX = contentView.bounds.origin.x
    }

    override func touchesMoved(with event: NSEvent) {
        guard let touch = event.touches(matching: .moved, in: self).first else { return }
        let delta = (touch.normalizedPosition.x - dragStartX) * max(1, bounds.width)
        scrollOrigin(to: dragStartOriginX - delta)
    }

    override func scrollWheel(with event: NSEvent) {
        scrollOrigin(to: contentView.bounds.origin.x - event.scrollingDeltaX)
    }

    private func scrollOrigin(to proposed: CGFloat) {
        let docWidth = documentView?.frame.width ?? 0
        let maxX = max(0, docWidth - contentView.bounds.width)
        let x = min(max(0, proposed), maxX)
        contentView.setBoundsOrigin(NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }

    private func clampScrollOrigin() { scrollOrigin(to: contentView.bounds.origin.x) }

    private func scrollToVisibleTab(_ view: NSView) {
        layoutSubtreeIfNeeded()
        let docWidth = documentView?.frame.width ?? 0
        let maxX = max(0, docWidth - contentView.bounds.width)
        let target = min(max(0, view.frame.midX - contentView.bounds.width / 2), maxX)
        scrollOrigin(to: target)
    }
}

/// A live volume slider for the expanded YouTube bar. Dragging sends an explicit
/// volume change; the compact mini-player keeps its mute toggle.
@MainActor
final class VolumeSliderView: NSView {
    private let slider: NSSlider
    private var onChange: (Int) -> Void

    init(volume: Int, isMuted: Bool, width: CGFloat = 116, onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
        self.slider = NSSlider(value: isMuted ? 0 : Double(volume), minValue: 0, maxValue: 100, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.setAccessibilityLabel("YouTube volume")
        addSubview(slider)
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    @objc private func sliderChanged() { onChange(Int(slider.doubleValue.rounded())) }
}

@MainActor
func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = secondary ? .secondaryLabelColor : .labelColor
    field.isSelectable = false
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
}

@MainActor
func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = spacing
    return stack
}

@MainActor
func textEditor(height: CGFloat, mono: Bool = false) -> (NSScrollView, NSTextView) {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: height))
    text.isRichText = false
    text.isAutomaticQuoteSubstitutionEnabled = false
    text.isAutomaticDashSubstitutionEnabled = false
    text.isAutomaticTextReplacementEnabled = false
    text.isContinuousSpellCheckingEnabled = !mono
    text.font = mono ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
    text.textContainerInset = NSSize(width: 10, height: 9)
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = false
    text.autoresizingMask = [.width]
    text.textContainer?.widthTracksTextView = true
    scroll.documentView = text
    return (scroll, text)
}

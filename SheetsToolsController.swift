import Cocoa

public enum SheetsToolItem: String, CaseIterable {
    // Page 1: Quick Formatting
    case currency = "Currency"
    case percent = "Percent"
    case bold = "Bold"
    case clearFormat = "Clear"

    // Page 2: Table Structure & Freeze
    case freezeRow = "Freeze Row"
    case freezeCol = "Freeze Col"
    case insertRow = "+ Row"
    case unfreeze = "Unfreeze"

    // Page 3: Data & Automation
    case filter = "Filter"
    case sortAZ = "Sort A→Z"
    case insertChart = "Chart"
    case appsScript = "Apps Script"

    // Page 4: Formulas
    case sumFormula = "=SUM"
    case avgFormula = "=AVERAGE"
    case vlookupFormula = "=VLOOKUP"
    case xlookupFormula = "=XLOOKUP"

    public var title: String {
        switch self {
        case .currency: return "$ Currency"
        case .percent: return "% Percent"
        case .bold: return "B Bold"
        case .clearFormat: return "⌫ Format"
        case .freezeRow: return "❄ Row"
        case .freezeCol: return "❄ Col"
        case .insertRow: return "+ Row"
        case .unfreeze: return "❄ Off"
        case .filter: return "⚡ Filter"
        case .sortAZ: return "Sort A-Z"
        case .insertChart: return "📊 Chart"
        case .appsScript: return "📜 Script"
        case .sumFormula: return "=SUM()"
        case .avgFormula: return "=AVG()"
        case .vlookupFormula: return "=VLOOKUP()"
        case .xlookupFormula: return "=XLOOKUP()"
        }
    }

    public var help: String {
        switch self {
        case .currency: return "Format cells as currency (Cmd+Shift+4)"
        case .percent: return "Format cells as percent (Cmd+Shift+5)"
        case .bold: return "Toggle bold (Cmd+B)"
        case .clearFormat: return "Clear cell formatting (Cmd+\\)"
        case .freezeRow: return "Freeze top row"
        case .freezeCol: return "Freeze first column"
        case .insertRow: return "Insert a row above (Cmd+Option+=)"
        case .unfreeze: return "Remove frozen rows and columns"
        case .filter: return "Toggle filter on active range"
        case .sortAZ: return "Sort range ascending"
        case .insertChart: return "Insert chart from selection"
        case .appsScript: return "Open Google Apps Script editor"
        case .sumFormula: return "Insert =SUM() formula"
        case .avgFormula: return "Insert =AVERAGE() formula"
        case .vlookupFormula: return "Insert =VLOOKUP() formula"
        case .xlookupFormula: return "Insert =XLOOKUP() formula"
        }
    }

    public var width: CGFloat {
        switch self {
        case .currency: return 70
        case .percent: return 68
        case .bold: return 55
        case .clearFormat: return 65
        case .freezeRow: return 60
        case .freezeCol: return 60
        case .insertRow: return 55
        case .unfreeze: return 55
        case .filter: return 65
        case .sortAZ: return 68
        case .insertChart: return 65
        case .appsScript: return 68
        case .sumFormula: return 65
        case .avgFormula: return 65
        case .vlookupFormula: return 80
        case .xlookupFormula: return 80
        }
    }
}

@MainActor
public final class SheetsToolsController {
    public static let shared = SheetsToolsController()

    public private(set) var currentPage: Int = 0
    public static let totalPages: Int = 4

    public init() {}

    public func nextPage() {
        currentPage = (currentPage + 1) % Self.totalPages
    }

    public func itemsForCurrentPage() -> [SheetsToolItem] {
        switch currentPage {
        case 0:
            return [.currency, .percent, .bold, .clearFormat]
        case 1:
            return [.freezeRow, .freezeCol, .insertRow, .unfreeze]
        case 2:
            return [.filter, .sortAZ, .insertChart, .appsScript]
        case 3:
            return [.sumFormula, .avgFormula, .vlookupFormula, .xlookupFormula]
        default:
            return [.currency, .percent, .bold, .clearFormat]
        }
    }

    public func execute(_ item: SheetsToolItem, currentURL: String?) {
        switch item {
        case .currency:
            // Cmd + Shift + 4
            sendKey(keyCode: 21, flags: [.maskCommand, .maskShift])
        case .percent:
            // Cmd + Shift + 5
            sendKey(keyCode: 23, flags: [.maskCommand, .maskShift])
        case .bold:
            // Cmd + B
            sendKey(keyCode: 11, flags: .maskCommand)
        case .clearFormat:
            // Cmd + \
            sendKey(keyCode: 42, flags: .maskCommand)
        case .insertRow:
            // Cmd + Option + =
            sendKey(keyCode: 24, flags: [.maskCommand, .maskAlternate])
        case .sumFormula:
            typeFormula("=SUM()")
        case .avgFormula:
            typeFormula("=AVERAGE()")
        case .vlookupFormula:
            typeFormula("=VLOOKUP()")
        case .xlookupFormula:
            typeFormula("=XLOOKUP()")
        case .freezeRow, .freezeCol, .unfreeze, .filter, .sortAZ, .insertChart:
            triggerWebAction(item)
        case .appsScript:
            openAppsScriptEditor(for: currentURL)
        }
    }

    // MARK: - Execution Helpers

    private func sendKey(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func typeFormula(_ formula: String) {
        // Types formula text into active spreadsheet cell
        for scalar in formula.utf16 {
            var unichar = scalar
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { continue }
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        // Send Left Arrow (key code 123) to place cursor inside the brackets
        sendKey(keyCode: 123)
    }

    private func triggerWebAction(_ item: SheetsToolItem) {
        // Many Sheets menu items can be triggered via keyboard navigation or menu search (Option+/)
        switch item {
        case .freezeRow:
            searchMenu("Freeze 1 row")
        case .freezeCol:
            searchMenu("Freeze 1 column")
        case .unfreeze:
            searchMenu("No rows")
        case .filter:
            searchMenu("Create a filter")
        case .sortAZ:
            searchMenu("Sort sheet A to Z")
        case .insertChart:
            searchMenu("Insert chart")
        default:
            break
        }
    }

    private func searchMenu(_ query: String) {
        // Option + / opens the "Search the menus" prompt in Google Sheets
        sendKey(keyCode: 44, flags: .maskAlternate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            for scalar in query.utf16 {
                var unichar = scalar
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { continue }
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            // Enter key (key code 36)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.sendKey(keyCode: 36)
            }
        }
    }

    private func openAppsScriptEditor(for url: String?) {
        guard let raw = url, !raw.isEmpty else {
            if let defaultScriptURL = URL(string: "https://script.google.com/home") {
                NSWorkspace.shared.open(defaultScriptURL)
            }
            return
        }

        // Extract spreadsheet ID from url: /spreadsheets/d/<ID>/...
        if let range = raw.range(of: "/spreadsheets/d/") {
            let sub = raw[range.upperBound...]
            let sheetID = sub.prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" })
            if !sheetID.isEmpty, let scriptURL = URL(string: "https://script.google.com/macros/d/\(sheetID)/edit") {
                NSWorkspace.shared.open(scriptURL)
                return
            }
        }

        if let fallbackURL = URL(string: "https://script.google.com/home") {
            NSWorkspace.shared.open(fallbackURL)
        }
    }
}

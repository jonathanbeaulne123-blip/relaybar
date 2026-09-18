import Cocoa

/// Toolbox: local text and data transforms over the clipboard.
///
/// Every tool reads the clipboard only when you tap it, and writes the result
/// back to the clipboard. RelayBar never pastes, never types and never sends.
/// Undo restores the previous clipboard value from a bounded in-memory stack.
@MainActor
public final class ToolboxController {
    private(set) var page = 0
    private var undoStack: [String] = []
    /// The last clipboard value RelayBar wrote, so a result can be described
    /// without re-reading the pasteboard.
    private(set) var lastSummary: String = ""

    public var onStatus: ((String) -> Void)?
    public var readClipboard: () -> String? = { NSPasteboard.general.string(forType: .string) }
    public var writeClipboard: (String) -> Bool = { text in
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    public init() {}

    public var pageCount: Int { ToolboxPolicy.pageCount }
    public var canUndo: Bool { !undoStack.isEmpty }

    public func toolsForCurrentPage() -> [ToolboxTool] { ToolboxPolicy.tools(on: page) }

    public func nextPage() { page = (page + 1) % max(1, ToolboxPolicy.pageCount) }

    public func run(_ tool: ToolboxTool) {
        let input = tool.usesClipboardInput ? (readClipboard() ?? "") : ""
        do {
            let result = try ToolboxPolicy.apply(tool, to: input)
            guard writeClipboard(result.text) else {
                onStatus?("The clipboard could not be written; nothing changed.")
                return
            }
            if tool.usesClipboardInput { pushUndo(input) }
            lastSummary = result.summary
            onStatus?("\(tool.title): \(result.summary). The result is on the clipboard; RelayBar never pastes it.")
        } catch {
            onStatus?(error.localizedDescription)
        }
    }

    public func undo() {
        guard let previous = undoStack.popLast() else {
            onStatus?("Nothing to undo yet.")
            return
        }
        guard writeClipboard(previous) else {
            onStatus?("The clipboard could not be restored.")
            return
        }
        onStatus?("Restored the previous clipboard text (\(previous.count) characters). RelayBar holds at most \(ToolboxPolicy.undoDepth) steps in memory.")
    }

    public func clearUndo() { undoStack.removeAll() }

    private func pushUndo(_ value: String) {
        if undoStack.last == value { return }
        undoStack.append(value)
        if undoStack.count > ToolboxPolicy.undoDepth { undoStack.removeFirst(undoStack.count - ToolboxPolicy.undoDepth) }
    }
}

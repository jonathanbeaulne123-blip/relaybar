import Foundation

/// Export the SAME catalog used by AppMain's Touch Bar and RB menu.
/// Run via Scripts/build_family_map.py; no app or assistant is opened.
@main
struct ExportButtonFamilies {
    static func main() throws {
        let pages: [[String: Any]] = RelayPage.allCases.map { page in
            let items: [[String: String]] = RelayHierarchy.items(on: page).map { item in
                switch item {
                case .page(let child): return ["kind": "group", "id": child.rawValue, "title": child.title, "help": "Open " + child.breadcrumb]
                case .command(let action): return ["kind": "action", "id": action.id, "title": action.title, "help": action.help]
                }
            }
            return ["id": page.rawValue, "title": page.title, "parent": page.parent?.rawValue ?? "", "breadcrumb": page.breadcrumb, "items": items]
        }
        let result: [String: Any] = ["release": "RelayBar 0.8.2 · Unified · Verified Click", "source": "Sources/Core/ButtonHierarchy.swift", "pages": pages]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}

import Foundation
import RiviuSyntax

/// A few lines of code from the indexed repository, to show in the hot path or a definition.
struct CodeExcerpt: Identifiable, Hashable {
    let path: String
    /// 0-based line of `lines[0]`.
    let firstLine: Int
    let lines: [String]
    /// 0-based lines this pull request added or changed, drawn tinted.
    let changedLines: Set<Int>
    /// The line to point at, like the call site.
    let focusLine: Int?

    var id: String { "\(path):\(firstLine)" }
    var fileName: String { (path as NSString).lastPathComponent }
    var isChanged: Bool { (firstLine..<(firstLine + lines.count)).contains { changedLines.contains($0) } }
}

/// A function on the hot path: who calls it, or what it calls.
struct HotPathItem: Identifiable, Hashable {
    /// The function containing the call (for callers) or the function called (for callees). nil at the top level.
    let function: SymbolLocation?
    let title: String
    let excerpt: CodeExcerpt

    var id: String { excerpt.id + title }
}

/// Works out callers and callees from the symbol index. Names are matched by text, so a call to a
/// same-named function elsewhere can show up too; that's why each item shows its code.
struct HotPathFinder {
    let index: SymbolIndex
    /// 0-based changed head lines, by path.
    let changedLines: (String) -> Set<Int>

    static let maxItems = 8

    /// The function the code is in.
    func focus(path: String, line: Int) -> SymbolLocation? {
        index.enclosingDefinition(path: path, line: line)
    }

    /// Functions that call `function`, once each, with a couple of lines around their first call.
    /// Code outside tests comes first, since that's the path the change affects in production.
    func callers(of function: SymbolLocation) -> [HotPathItem] {
        var seen = Set<String>()
        var items: [HotPathItem] = []
        let calls = index.calls(to: function.name)
            .filter { !($0.path == function.path && function.lines.contains($0.lines.lowerBound)) }
            .sorted { (Self.isTest($0.path) ? 1 : 0, $0.path, $0.lines.lowerBound) < (Self.isTest($1.path) ? 1 : 0, $1.path, $1.lines.lowerBound) }
        for call in calls {
            let caller = index.enclosingDefinition(path: call.path, line: call.lines.lowerBound)
            let key = caller.map { "\($0.path):\($0.lines.lowerBound)" } ?? "\(call.path):\(call.lines.lowerBound)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let line = call.lines.lowerBound
            items.append(HotPathItem(function: caller, title: caller.map { "\($0.name)()" } ?? "top level",
                                     excerpt: excerpt(path: call.path, lines: (line - 2)...(line + 2), focus: line)))
            if items.count == Self.maxItems { break }
        }
        return items
    }

    private static func isTest(_ path: String) -> Bool {
        path.localizedCaseInsensitiveContains("test") || path.localizedCaseInsensitiveContains("spec")
    }

    /// Functions called inside some lines, each with the start of its definition.
    func callees(inside lines: ClosedRange<Int>, of path: String, excluding function: SymbolLocation?) -> [HotPathItem] {
        var seen = Set<String>()
        var items: [HotPathItem] = []
        for call in index.calls(inside: lines, of: path) where !seen.contains(call.name) && call.name != function?.name {
            seen.insert(call.name)
            let definitions = index.definitions(named: call.name).filter(\.isCallable)
            // Prefer a definition in the same file, which is most likely the one meant.
            guard let definition = definitions.first(where: { $0.path == path }) ?? definitions.first else { continue }
            let shown = definition.lines.lowerBound...min(definition.lines.upperBound, definition.lines.lowerBound + 9)
            items.append(HotPathItem(function: definition, title: "\(definition.name)()",
                                     excerpt: excerpt(path: definition.path, lines: shown, focus: nil)))
            if items.count == Self.maxItems { break }
        }
        return items
    }

    func excerpt(path: String, lines: ClosedRange<Int>, focus: Int?) -> CodeExcerpt {
        let first = max(0, lines.lowerBound)
        let text = index.lines(first...max(first, lines.upperBound), of: path) ?? []
        return CodeExcerpt(path: path, firstLine: first, lines: text, changedLines: changedLines(path), focusLine: focus)
    }
}

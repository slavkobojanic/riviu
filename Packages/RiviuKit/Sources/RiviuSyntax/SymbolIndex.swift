import Foundation
import SwiftTreeSitter

/// A definition (like a function) or a reference (like a call) found in a file.
public struct SymbolLocation: Sendable, Hashable {
    public let name: String
    /// From the tags query: "function", "method", "class", "call", "type"…
    public let kind: String
    public let path: String
    /// 0-based lines the whole definition or reference spans.
    public let lines: ClosedRange<Int>
    public let isDefinition: Bool

    /// Definitions of things that run, as opposed to types.
    public var isCallable: Bool { isDefinition && ["function", "method", "macro"].contains(kind) }
}

/// Where things are defined and called across a set of files, from each grammar's tags query.
/// Build it once per commit with `SymbolIndex.build(files:)`; afterwards it is safe to share.
public final class SymbolIndex: Sendable {
    public let fileCount: Int
    private let definitionsByName: [String: [SymbolLocation]]
    private let callsByName: [String: [SymbolLocation]]
    private let symbolsByPath: [String: [SymbolLocation]]
    private let linesByPath: [String: [String]]

    /// Parses every file in a supported language, in parallel.
    public static func build(files: [(path: String, text: String)]) async -> SymbolIndex {
        let found = await withTaskGroup(of: (String, [String], [SymbolLocation]).self) { group in
            for file in files {
                guard let language = SyntaxLanguage.detect(path: file.path) else { continue }
                group.addTask {
                    let lines = file.text.components(separatedBy: "\n")
                    return (file.path, lines, symbols(in: file.text, path: file.path, language: language))
                }
            }
            var results: [(String, [String], [SymbolLocation])] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        return SymbolIndex(found: found)
    }

    private init(found: [(path: String, lines: [String], symbols: [SymbolLocation])]) {
        fileCount = found.count
        var definitions: [String: [SymbolLocation]] = [:]
        var calls: [String: [SymbolLocation]] = [:]
        var byPath: [String: [SymbolLocation]] = [:]
        var lines: [String: [String]] = [:]
        for file in found {
            lines[file.path] = file.lines
            byPath[file.path] = file.symbols
            for symbol in file.symbols {
                if symbol.isDefinition {
                    definitions[symbol.name, default: []].append(symbol)
                } else if symbol.kind == "call" {
                    calls[symbol.name, default: []].append(symbol)
                }
            }
        }
        definitionsByName = definitions
        callsByName = calls
        symbolsByPath = byPath
        linesByPath = lines
    }

    public func definitions(named name: String) -> [SymbolLocation] {
        definitionsByName[name] ?? []
    }

    public func calls(to name: String) -> [SymbolLocation] {
        callsByName[name] ?? []
    }

    /// The innermost function or method containing a line, or nil at the top level.
    public func enclosingDefinition(path: String, line: Int) -> SymbolLocation? {
        (symbolsByPath[path] ?? [])
            .filter { $0.isCallable && $0.lines.contains(line) }
            .min { $0.lines.count < $1.lines.count }
    }

    /// Calls made inside some lines of a file, in order.
    public func calls(inside lines: ClosedRange<Int>, of path: String) -> [SymbolLocation] {
        (symbolsByPath[path] ?? [])
            .filter { $0.kind == "call" && lines.contains($0.lines.lowerBound) }
            .sorted { $0.lines.lowerBound < $1.lines.lowerBound }
    }

    /// Some lines of an indexed file, or nil if it isn't indexed.
    public func lines(_ range: ClosedRange<Int>, of path: String) -> [String]? {
        guard let lines = linesByPath[path], !lines.isEmpty else { return nil }
        let clamped = max(0, range.lowerBound)...min(lines.count - 1, range.upperBound)
        return clamped.isEmpty ? [] : Array(lines[clamped])
    }

    public func contains(path: String) -> Bool {
        linesByPath[path] != nil
    }

    // MARK: - Parsing

    private static func symbols(in text: String, path: String, language: SyntaxLanguage) -> [SymbolLocation] {
        guard let grammar = SyntaxLanguageRegistry.grammar(for: language),
              let query = SyntaxLanguageRegistry.shared.tagsQuery(for: language) else { return [] }
        let parser = Parser()
        guard (try? parser.setLanguage(grammar)) != nil, let mutable = parser.parse(text), let tree = mutable.copy() else { return [] }
        let utf16 = text.utf16
        var result: [SymbolLocation] = []
        for match in query.execute(in: tree).resolve(with: .init(string: text)) {
            guard let nameCapture = match.captures.first(where: { $0.name == "name" }),
                  let tag = match.captures.first(where: { ($0.name ?? "").hasPrefix("definition.") || ($0.name ?? "").hasPrefix("reference.") }),
                  let tagName = tag.name else { continue }
            let range = nameCapture.node.range
            guard let start = utf16.index(utf16.startIndex, offsetBy: range.location, limitedBy: utf16.endIndex),
                  let end = utf16.index(start, offsetBy: range.length, limitedBy: utf16.endIndex),
                  let name = String(utf16[start..<end]), !name.isEmpty else { continue }
            let parts = tagName.split(separator: ".", maxSplits: 1)
            let points = tag.node.pointRange
            let firstLine = Int(points.lowerBound.row)
            let lastLine = max(firstLine, Int(points.upperBound.row))
            result.append(SymbolLocation(name: name, kind: parts.count > 1 ? String(parts[1]) : "", path: path,
                                         lines: firstLine...lastLine, isDefinition: parts[0] == "definition"))
        }
        return result
    }
}

import Foundation
import SwiftTreeSitter
import Synchronization
import TreeSitterGo
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterMarkdown
import TreeSitterPython
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript

/// Languages with a bundled tree-sitter grammar + highlight queries.
public enum SyntaxLanguage: String, CaseIterable, Sendable {
    case swift, typescript, tsx, javascript, python, go, rust, json, markdown

    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .typescript: "TypeScript"
        case .tsx: "TSX"
        case .javascript: "JavaScript"
        case .python: "Python"
        case .go: "Go"
        case .rust: "Rust"
        case .json: "JSON"
        case .markdown: "Markdown"
        }
    }

    public static func detect(path: String) -> SyntaxLanguage? {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": .swift
        case "ts", "mts", "cts": .typescript
        case "tsx": .tsx
        case "js", "jsx", "mjs", "cjs": .javascript
        case "py", "pyi": .python
        case "go": .go
        case "rs": .rust
        case "json", "jsonc": .json
        case "md", "markdown": .markdown
        default: nil
        }
    }

    /// Loaded lazily and cached; configurations are immutable and Sendable.
    var configuration: LanguageConfiguration? {
        SyntaxLanguageRegistry.shared.configuration(for: self)
    }
}

final class SyntaxLanguageRegistry: Sendable {
    static let shared = SyntaxLanguageRegistry()

    private let cache = Mutex<[SyntaxLanguage: LanguageConfiguration?]>([:])
    private let tagsCache = Mutex<[SyntaxLanguage: Query?]>([:])

    func configuration(for language: SyntaxLanguage) -> LanguageConfiguration? {
        if let hit = cache.withLock({ $0[language] }) { return hit }
        let made = Self.make(language)
        cache.withLock { $0[language] = made }
        return made
    }

    private static func make(_ language: SyntaxLanguage) -> LanguageConfiguration? {
        do {
            switch language {
            case .swift: return try LanguageConfiguration(tree_sitter_swift(), name: "Swift")
            case .javascript:
                return try combined(tree_sitter_javascript(), name: "JavaScript",
                                    highlightFiles: [("JavaScript", "highlights.scm"), ("JavaScript", "highlights-jsx.scm")])
            // The TypeScript grammars extend JavaScript; their highlights.scm only adds TS-specific captures.
            case .typescript:
                return try combined(tree_sitter_typescript(), name: "TypeScript",
                                    highlightFiles: [("JavaScript", "highlights.scm"), ("TypeScript", "highlights.scm")])
            case .tsx:
                return try combined(tree_sitter_tsx(), name: "TSX",
                                    highlightFiles: [("JavaScript", "highlights.scm"), ("JavaScript", "highlights-jsx.scm"),
                                                     ("TypeScript", "highlights.scm")])
            case .python: return try LanguageConfiguration(tree_sitter_python(), name: "Python")
            case .go: return try LanguageConfiguration(tree_sitter_go(), name: "Go")
            case .rust: return try LanguageConfiguration(tree_sitter_rust(), name: "Rust")
            case .json: return try LanguageConfiguration(tree_sitter_json(), name: "JSON")
            case .markdown: return try LanguageConfiguration(tree_sitter_markdown(), name: "Markdown")
            }
        } catch {
            print("RiviuSyntax: failed to load \(language): \(error)")
            return nil
        }
    }

    /// Builds a configuration whose highlights query concatenates several packages' `.scm` files.
    private static func combined(_ ts: OpaquePointer, name: String, highlightFiles: [(package: String, file: String)]) throws -> LanguageConfiguration {
        let language = Language(ts)
        var source = Data()
        for (package, file) in highlightFiles {
            if let data = try? Data(contentsOf: queriesURL(package: package).appending(path: file)) {
                source.append(data)
                source.append(contentsOf: Array("\n".utf8))
            }
        }
        return LanguageConfiguration(language, name: name, queries: [.highlights: try Query(language: language, data: source)])
    }

    /// The grammar package's bundled "queries" folder: inside the app, or next to the test bundle in `swift test`.
    private static func queriesURL(package: String, target: String? = nil) -> URL {
        let bundle = "TreeSitter\(package)_TreeSitter\(target ?? package).bundle"
        let candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                          Bundle(for: SyntaxLanguageRegistry.self).bundleURL.deletingLastPathComponent()].compactMap(\.self)
        let urls = candidates.map { $0.appending(path: "\(bundle)/Contents/Resources/queries", directoryHint: .isDirectory) }
        return urls.first { FileManager.default.fileExists(atPath: $0.path) } ?? urls[0]
    }

    /// tree-sitter-swift's tags.scm only lists definitions; Riviu also needs calls for the hot path.
    private static let swiftCalls = """
    (call_expression (simple_identifier) @name) @reference.call
    (call_expression (navigation_expression (navigation_suffix (simple_identifier) @name))) @reference.call

    """

    /// Just the grammar, without the highlight queries that `configuration` also loads.
    static func grammar(for language: SyntaxLanguage) -> Language? {
        switch language {
        case .swift: Language(tree_sitter_swift())
        case .typescript: Language(tree_sitter_typescript())
        case .tsx: Language(tree_sitter_tsx())
        case .javascript: Language(tree_sitter_javascript())
        case .python: Language(tree_sitter_python())
        case .go: Language(tree_sitter_go())
        case .rust: Language(tree_sitter_rust())
        case .json: Language(tree_sitter_json())
        case .markdown: Language(tree_sitter_markdown())
        }
    }

    /// The tags query, which finds definitions and calls, for the symbol index.
    func tagsQuery(for language: SyntaxLanguage) -> Query? {
        if let hit = tagsCache.withLock({ $0[language] }) { return hit }
        let made = Self.makeTagsQuery(language)
        tagsCache.withLock { $0[language] = made }
        return made
    }

    private static func makeTagsQuery(_ language: SyntaxLanguage) -> Query? {
        let files: [(package: String, target: String?)] = switch language {
        case .swift: [("Swift", nil)]
        case .javascript: [("JavaScript", nil)]
        case .typescript: [("JavaScript", nil), ("TypeScript", nil)]
        case .tsx: [("JavaScript", nil), ("TypeScript", "TSX")]
        case .python: [("Python", nil)]
        case .go: [("Go", nil)]
        case .rust: [("Rust", nil)]
        case .json, .markdown: []
        }
        guard !files.isEmpty, let grammar = grammar(for: language) else { return nil }
        var source = Data()
        for file in files {
            if let data = try? Data(contentsOf: queriesURL(package: file.package, target: file.target).appending(path: "tags.scm")) {
                source.append(data)
                source.append(contentsOf: Array("\n".utf8))
            }
        }
        if language == .swift {
            source.append(contentsOf: Array(swiftCalls.utf8))
        }
        do {
            return try Query(language: grammar, data: source)
        } catch {
            print("RiviuSyntax: couldn't load tags for \(language): \(error)")
            return nil
        }
    }
}

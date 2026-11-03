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

    private static func queriesURL(package: String) -> URL {
        let bundle = "TreeSitter\(package)_TreeSitter\(package).bundle"
        let base = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        return base.appending(path: "\(bundle)/Contents/Resources/queries", directoryHint: .isDirectory)
    }
}

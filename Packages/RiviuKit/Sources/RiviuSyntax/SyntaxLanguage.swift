import Foundation
import SwiftTreeSitter
import Synchronization
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSharp
import TreeSitterCSS
import TreeSitterElixir
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterKotlin
import TreeSitterLua
import TreeSitterMarkdown
import TreeSitterPHP
import TreeSitterPython
import TreeSitterRuby
import TreeSitterRust
import TreeSitterScala
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

/// Languages with a bundled tree-sitter grammar + highlight queries.
public enum SyntaxLanguage: String, CaseIterable, Sendable {
    case swift, typescript, tsx, javascript, python, go, rust, json, markdown
    case c, cpp, csharp, java, kotlin, scala, ruby, php, bash, html, css, yaml, toml, lua, elixir

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
        case .c: "C"
        case .cpp: "C++"
        case .csharp: "C#"
        case .java: "Java"
        case .kotlin: "Kotlin"
        case .scala: "Scala"
        case .ruby: "Ruby"
        case .php: "PHP"
        case .bash: "Shell"
        case .html: "HTML"
        case .css: "CSS"
        case .yaml: "YAML"
        case .toml: "TOML"
        case .lua: "Lua"
        case .elixir: "Elixir"
        }
    }

    public static func detect(path: String) -> SyntaxLanguage? {
        let fileName = (path as NSString).lastPathComponent
        switch fileName {
        case "Gemfile", "Rakefile", "Podfile", "Fastfile", "Brewfile", "Guardfile", "Vagrantfile", "Dangerfile": return .ruby
        case ".bashrc", ".bash_profile", ".zshrc", ".zprofile", ".profile", "PKGBUILD": return .bash
        case "Cargo.lock", "Pipfile", "poetry.lock", "uv.lock": return .toml
        case ".clang-format", ".clang-tidy", ".swiftlint.yml": return .yaml
        default: break
        }
        return switch (fileName as NSString).pathExtension.lowercased() {
        case "swift": .swift
        case "ts", "mts", "cts": .typescript
        case "tsx": .tsx
        case "js", "jsx", "mjs", "cjs": .javascript
        case "py", "pyi": .python
        case "go": .go
        case "rs": .rust
        case "json", "jsonc": .json
        case "md", "markdown": .markdown
        case "c": .c
        // `.h` is shared by C, C++ and Objective-C; the C++ grammar reads all of them reasonably.
        case "h", "cc", "cpp", "cxx", "c++", "hh", "hpp", "hxx", "h++", "ipp", "tpp", "inl", "m", "mm": .cpp
        case "cs", "csx": .csharp
        case "java": .java
        case "kt", "kts": .kotlin
        case "scala", "sc", "sbt": .scala
        case "rb", "rake", "gemspec", "ru", "podspec", "jbuilder": .ruby
        case "php", "phtml": .php
        case "sh", "bash", "zsh", "ksh", "command": .bash
        case "html", "htm", "xhtml": .html
        case "css": .css
        case "yml", "yaml": .yaml
        case "toml": .toml
        case "lua": .lua
        case "ex", "exs": .elixir
        default: nil
        }
    }

    /// Loaded lazily and cached; configurations are immutable and Sendable.
    var configuration: LanguageConfiguration? {
        SyntaxLanguageRegistry.shared.configuration(for: self)
    }
}

/// Where a language's grammar and queries come from.
private struct GrammarSource {
    let grammar: () -> OpaquePointer?
    /// The grammar's Swift package, as in its `TreeSitter<package>` product name.
    let package: String
    /// The `.scm` files that make up the highlights query. A grammar that extends another
    /// (TypeScript extends JavaScript, C++ extends C) lists the base language's file first.
    let highlights: [QueryFile]
    /// The files that make up the tags query, which finds definitions and calls. Empty when there are none.
    let tags: [QueryFile]

    init(_ grammar: @escaping () -> OpaquePointer?, package: String, highlights: [QueryFile]? = nil, tags: [QueryFile]) {
        self.grammar = grammar
        self.package = package
        self.highlights = highlights ?? [QueryFile(package, "highlights.scm")]
        self.tags = tags
    }

    /// A grammar whose own `highlights.scm` is complete, with its own `tags.scm` when `hasTags`.
    init(_ grammar: @escaping () -> OpaquePointer?, package: String, hasTags: Bool) {
        self.init(grammar, package: package, tags: hasTags ? [QueryFile(package, "tags.scm")] : [])
    }
}

private struct QueryFile {
    let package: String
    let target: String?
    let file: String

    init(_ package: String, target: String? = nil, _ file: String) {
        self.package = package
        self.target = target
        self.file = file
    }
}

extension SyntaxLanguage {
    fileprivate var source: GrammarSource {
        switch self {
        case .swift: GrammarSource(tree_sitter_swift, package: "Swift", hasTags: true)
        case .javascript:
            GrammarSource(tree_sitter_javascript, package: "JavaScript",
                          highlights: [QueryFile("JavaScript", "highlights.scm"), QueryFile("JavaScript", "highlights-jsx.scm")],
                          tags: [QueryFile("JavaScript", "tags.scm")])
        // The TypeScript grammars extend JavaScript; their highlights.scm only adds TS-specific captures.
        case .typescript:
            GrammarSource(tree_sitter_typescript, package: "TypeScript",
                          highlights: [QueryFile("JavaScript", "highlights.scm"), QueryFile("TypeScript", "highlights.scm")],
                          tags: [QueryFile("JavaScript", "tags.scm"), QueryFile("TypeScript", "tags.scm")])
        case .tsx:
            GrammarSource(tree_sitter_tsx, package: "TSX",
                          highlights: [QueryFile("JavaScript", "highlights.scm"), QueryFile("JavaScript", "highlights-jsx.scm"),
                                       QueryFile("TypeScript", "highlights.scm")],
                          tags: [QueryFile("JavaScript", "tags.scm"), QueryFile("TypeScript", target: "TSX", "tags.scm")])
        case .python: GrammarSource(tree_sitter_python, package: "Python", hasTags: true)
        case .go: GrammarSource(tree_sitter_go, package: "Go", hasTags: true)
        case .rust: GrammarSource(tree_sitter_rust, package: "Rust", hasTags: true)
        case .json: GrammarSource(tree_sitter_json, package: "JSON", hasTags: false)
        case .markdown: GrammarSource(tree_sitter_markdown, package: "Markdown", hasTags: false)
        case .c: GrammarSource(tree_sitter_c, package: "C", hasTags: true)
        // The C++ grammar extends C; its highlights.scm only adds C++-specific captures.
        case .cpp:
            GrammarSource(tree_sitter_cpp, package: "CPP",
                          highlights: [QueryFile("C", "highlights.scm"), QueryFile("CPP", "highlights.scm")],
                          tags: [QueryFile("CPP", "tags.scm")])
        case .csharp: GrammarSource(tree_sitter_c_sharp, package: "CSharp", hasTags: true)
        case .java: GrammarSource(tree_sitter_java, package: "Java", hasTags: true)
        case .kotlin: GrammarSource(tree_sitter_kotlin, package: "Kotlin", hasTags: false)
        case .scala: GrammarSource(tree_sitter_scala, package: "Scala", hasTags: true)
        case .ruby: GrammarSource(tree_sitter_ruby, package: "Ruby", hasTags: true)
        case .php: GrammarSource(tree_sitter_php, package: "PHP", hasTags: true)
        case .bash: GrammarSource(tree_sitter_bash, package: "Bash", hasTags: false)
        case .html: GrammarSource(tree_sitter_html, package: "HTML", hasTags: false)
        case .css: GrammarSource(tree_sitter_css, package: "CSS", hasTags: false)
        case .yaml: GrammarSource(tree_sitter_yaml, package: "YAML", hasTags: false)
        case .toml: GrammarSource(tree_sitter_toml, package: "TOML", hasTags: false)
        case .lua: GrammarSource(tree_sitter_lua, package: "Lua", hasTags: true)
        case .elixir: GrammarSource(tree_sitter_elixir, package: "Elixir", hasTags: true)
        }
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
        let source = language.source
        guard let pointer = source.grammar() else { return nil }
        let grammar = Language(pointer)
        do {
            let query = try Query(language: grammar, data: queryData(source.highlights))
            return LanguageConfiguration(grammar, name: source.package, queries: [.highlights: query])
        } catch {
            print("RiviuSyntax: failed to load \(language): \(error)")
            return nil
        }
    }

    /// Concatenates `.scm` files from the grammar packages' bundled "queries" folders.
    private static func queryData(_ files: [QueryFile]) -> Data {
        var data = Data()
        for file in files {
            if let contents = try? Data(contentsOf: queriesURL(package: file.package, target: file.target).appending(path: file.file)) {
                data.append(contents)
                data.append(contentsOf: Array("\n".utf8))
            }
        }
        return data
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
        language.source.grammar().map { Language($0) }
    }

    /// The tags query, which finds definitions and calls, for the symbol index.
    func tagsQuery(for language: SyntaxLanguage) -> Query? {
        if let hit = tagsCache.withLock({ $0[language] }) { return hit }
        let made = Self.makeTagsQuery(language)
        tagsCache.withLock { $0[language] = made }
        return made
    }

    private static func makeTagsQuery(_ language: SyntaxLanguage) -> Query? {
        let files = language.source.tags
        guard !files.isEmpty, let grammar = grammar(for: language) else { return nil }
        var source = queryData(files)
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

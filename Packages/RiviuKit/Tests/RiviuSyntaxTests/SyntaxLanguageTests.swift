import Testing
@testable import RiviuSyntax

struct SyntaxLanguageTests {
    /// A line in each language that should contain a keyword, string or other highlighted token.
    static let samples: [SyntaxLanguage: String] = [
        .swift: "let name = \"Riviu\"",
        .typescript: "const name: string = \"Riviu\"",
        .tsx: "const view = <div className=\"x\" />",
        .javascript: "const name = \"Riviu\"",
        .python: "def greet(name): return \"hi\"",
        .go: "func main() { fmt.Println(\"hi\") }",
        .rust: "fn main() { let x = 1; }",
        .json: "{\"name\": \"Riviu\", \"count\": 2}",
        .markdown: "# Title",
        .c: "int main(void) { return 0; }",
        .cpp: "class Foo { public: virtual ~Foo(); };",
        .csharp: "public class Foo { void Bar() { var x = \"hi\"; } }",
        .java: "public class Foo { void bar() { String x = \"hi\"; } }",
        .kotlin: "fun main() { val x = \"hi\" }",
        .scala: "object Main { def run(): Unit = println(\"hi\") }",
        .ruby: "def greet(name) = puts \"hi\"",
        .php: "<?php function greet($name) { return \"hi\"; }",
        .bash: "if [ -f \"$file\" ]; then echo hi; fi",
        .html: "<div class=\"note\">Hi</div>",
        .css: ".note { color: red; margin: 4px; }",
        .yaml: "name: Riviu\ncount: 2",
        .toml: "[package]\nname = \"riviu\"",
        .lua: "local function greet(name) return \"hi\" end",
        .elixir: "defmodule Greeter do\n  def hi, do: \"hi\"\nend",
    ]

    @Test(arguments: SyntaxLanguage.allCases)
    func highlights(_ language: SyntaxLanguage) throws {
        let sample = try #require(Self.samples[language], "add a sample for \(language)")
        #expect(language.configuration?.queries[.highlights] != nil)
        let lines = sample.components(separatedBy: "\n")
        let document = SyntaxDocument(lines: lines, language: language)
        #expect(lines.indices.contains { !document.tokens(line: $0).isEmpty }, "no highlights for \(language)")
    }

    @Test func loadsTagsQueries() {
        let withTags: [SyntaxLanguage] = [.swift, .typescript, .tsx, .javascript, .python, .go, .rust, .c, .cpp, .csharp,
                                          .java, .scala, .ruby, .php, .lua, .elixir]
        for language in withTags {
            #expect(SyntaxLanguageRegistry.shared.tagsQuery(for: language) != nil, "no tags for \(language)")
        }
    }

    @Test func detectsLanguages() {
        #expect(SyntaxLanguage.detect(path: "src/main.cpp") == .cpp)
        #expect(SyntaxLanguage.detect(path: "include/thing.h") == .cpp)
        #expect(SyntaxLanguage.detect(path: "App/Program.cs") == .csharp)
        #expect(SyntaxLanguage.detect(path: "build.gradle.kts") == .kotlin)
        #expect(SyntaxLanguage.detect(path: "Gemfile") == .ruby)
        #expect(SyntaxLanguage.detect(path: ".github/workflows/ci.yml") == .yaml)
        #expect(SyntaxLanguage.detect(path: "scripts/release.sh") == .bash)
        #expect(SyntaxLanguage.detect(path: "Cargo.lock") == .toml)
        #expect(SyntaxLanguage.detect(path: "LICENSE") == nil)
    }
}

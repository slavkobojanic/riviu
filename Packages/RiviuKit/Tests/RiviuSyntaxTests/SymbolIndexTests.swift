import Testing
@testable import RiviuSyntax

struct SymbolIndexTests {
    @Test func findsDefinitionsAndCallsAcrossFiles() async {
        let store = """
        func refresh() {
            let token = fetchToken()
            save(token)
        }

        func fetchToken() -> String {
            "abc"
        }
        """
        let caller = """
        func start() {
            refresh()
        }
        """
        let index = await SymbolIndex.build(files: [("Store.swift", store), ("App.swift", caller)])
        #expect(index.fileCount == 2)
        #expect(index.definitions(named: "fetchToken").first?.lines == 5...7)
        #expect(index.calls(to: "refresh").first?.path == "App.swift")
        #expect(index.enclosingDefinition(path: "Store.swift", line: 2)?.name == "refresh")
        #expect(index.calls(inside: 0...3, of: "Store.swift").map(\.name).contains("fetchToken"))
    }

    @Test func swiftMethodsSpanJustTheMethod() async {
        let swift = """
        final class Store {
            let name = "store"

            func refresh() {
                save()
            }
        }
        """
        let index = await SymbolIndex.build(files: [("Store.swift", swift)])
        #expect(index.definitions(named: "refresh").map(\.lines) == [3...5])
        #expect(index.enclosingDefinition(path: "Store.swift", line: 1) == nil)
        #expect(index.enclosingDefinition(path: "Store.swift", line: 4)?.name == "refresh")
    }

    @Test func indexesGoAndPython() async {
        let go = "package main\n\nfunc Handle() {\n\tqueue()\n}\n\nfunc queue() {}\n"
        let python = "def sync():\n    fetch_page()\n\ndef fetch_page():\n    pass\n"
        let index = await SymbolIndex.build(files: [("main.go", go), ("sync.py", python)])
        #expect(index.calls(to: "queue").first?.path == "main.go")
        #expect(index.enclosingDefinition(path: "sync.py", line: 1)?.name == "sync")
        #expect(index.definitions(named: "fetch_page").count == 1)
    }
}

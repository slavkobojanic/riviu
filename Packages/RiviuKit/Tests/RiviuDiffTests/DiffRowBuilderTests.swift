import Testing
@testable import RiviuDiff

struct DiffRowBuilderTests {
    private let file = FileDiff(
        path: "a.swift", status: .modified,
        baseLines: (1...20).map { "line \($0)" },
        headLines: (1...10).map { "line \($0)" } + ["new 1", "new 2"] + (11...20).map { "line \($0)" }
    )

    @Test func splitViewPadsTheShorterSideWithFillers() {
        let small = FileDiff(path: "b.swift", status: .modified, baseLines: ["a", "old", "c"], headLines: ["a", "new 1", "new 2", "c"])
        let rows = DiffRowBuilder.rows(for: small, options: DiffRowOptions())
        guard case let .split(base, head) = rows[2] else { Issue.record("expected a split row"); return }
        #expect(base == nil)
        #expect(head?.text == "new 2")
    }

    @Test func longUnchangedRunsCollapseAroundChanges() {
        var options = DiffRowOptions()
        options.contextLines = 2
        let rows = DiffRowBuilder.rows(for: file, options: options)
        // 10 unchanged lines before the change: 8 hidden, 2 shown. Same after it.
        let collapsed = rows.compactMap { row -> Int? in
            if case let .collapsed(_, hidden, _) = row { return hidden }
            return nil
        }
        #expect(collapsed == [8, 8])
        #expect(rows.count == 1 + 2 + 2 + 2 + 1)
    }

    @Test func expandAllShowsEveryLine() {
        var options = DiffRowOptions()
        options.expandAll = true
        #expect(DiffRowBuilder.rows(for: file, options: options).count == 22)
    }

    @Test func unifiedViewListsRemovalsBeforeAdditions() {
        let small = FileDiff(path: "b.swift", status: .modified, baseLines: ["old"], headLines: ["new"])
        var options = DiffRowOptions()
        options.layout = .unified
        let kinds = DiffRowBuilder.rows(for: small, options: options).compactMap { row -> DiffLine.Kind? in
            if case let .unified(line, _, _) = row { return line.kind }
            return nil
        }
        #expect(kinds == [.removed, .added])
    }

    @Test func attachmentsGoBelowTheirLineAndExpandHiddenLines() {
        let attachment = Attachment(id: AttachmentID("note"), side: .head, lineIndex: 2)
        let rows = DiffRowBuilder.rows(for: file, options: DiffRowOptions(), attachments: [attachment])
        let index = rows.firstIndex { if case .attachment = $0 { true } else { false } }
        #expect(index == 3)
        #expect(rows[2].lineIndices?.head == 2)
    }
}

struct FileTreeNodeTests {
    @Test func foldersComeFirstAndSingleChildChainsAreMerged() {
        let tree = FileTreeNode.tree(for: ["README.md", "crates/core/src/lib.rs", "Sources/App/main.swift", "Sources/App/View.swift"])
        #expect(tree.map(\.name) == ["crates/core/src", "Sources/App", "README.md"])
        #expect(tree[1].children?.map(\.name) == ["main.swift", "View.swift"])
        #expect(tree[1].children?.first?.id == "Sources/App/main.swift")
    }
}

struct UnifiedDiffTextTests {
    @Test func rendersChangesWithContext() {
        let file = FileDiff(path: "a.txt", status: .modified, baseLines: ["a", "b", "c"], headLines: ["a", "B", "c"])
        #expect(UnifiedDiffText.make(for: file) == "--- a/a.txt\n+++ b/a.txt\n a\n-b\n+B\n c")
    }
}

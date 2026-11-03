import Testing
@testable import RiviuDiff

struct LineDiffTests {
    @Test func identicalFilesHaveOneUnchangedSegment() {
        let lines = ["a", "b", "c"]
        #expect(LineDiff.segments(base: lines, head: lines) == [.unchanged(base: 0..<3, head: 0..<3)])
    }

    @Test func insertionInTheMiddle() {
        let segments = LineDiff.segments(base: ["a", "b"], head: ["a", "x", "b"])
        #expect(segments == [
            .unchanged(base: 0..<1, head: 0..<1),
            .changed(removed: 1..<1, added: 1..<2),
            .unchanged(base: 1..<2, head: 2..<3),
        ])
    }

    @Test func modifiedLineIsOneRemovalAndOneAddition() {
        let segments = LineDiff.segments(base: ["a", "b", "c"], head: ["a", "B", "c"])
        #expect(segments == [
            .unchanged(base: 0..<1, head: 0..<1),
            .changed(removed: 1..<2, added: 1..<2),
            .unchanged(base: 2..<3, head: 2..<3),
        ])
    }

    @Test func addedAndDeletedFiles() {
        #expect(LineDiff.segments(base: [], head: ["a", "b"]) == [.changed(removed: 0..<0, added: 0..<2)])
        #expect(LineDiff.segments(base: ["a"], head: []) == [.changed(removed: 0..<1, added: 0..<0)])
        #expect(LineDiff.segments(base: [], head: []).isEmpty)
    }

    @Test func fileDiffCountsAdditionsAndDeletions() {
        let file = FileDiff(path: "a.swift", status: .modified, baseLines: ["a", "b", "c"], headLines: ["a", "x", "y", "c"])
        #expect(file.additions == 2)
        #expect(file.deletions == 1)
    }
}

struct WordChangeTests {
    @Test func findsTheChangedWord() {
        let ranges = WordChange.changedRanges(old: "let value = 1", new: "let value = 42")
        #expect(ranges?.old == 12..<13)
        #expect(ranges?.new == 12..<14)
    }

    @Test func ignoresIdenticalAndRewrittenLines() {
        #expect(WordChange.changedRanges(old: "same", new: "same") == nil)
        #expect(WordChange.changedRanges(old: "abcdef", new: "uvwxyz") == nil)
    }
}

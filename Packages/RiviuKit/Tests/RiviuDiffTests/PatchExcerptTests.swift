import Testing
@testable import RiviuDiff

struct PatchExcerptTests {
    let patch = """
    @@ -10,4 +10,4 @@
     let a = 1
    -let b = 2
    +let b = 3
     let c = 4
    -let d = 5
    +let d = 6
    """

    @Test func keepsTheRemovedLineBeforeTheRangeAndDropsTheOneAfter() {
        let lines = PatchExcerpt.lines(in: patch, side: .head, range: 11...12)
        #expect(lines.map(\.text) == ["let b = 2", "let b = 3", "let c = 4"])
        #expect(lines.map(\.kind) == [.removed, .added, .context])
        #expect(lines.last?.newNumber == 12)
    }

    @Test func cutsByOldLineNumbersOnTheBaseSide() {
        let lines = PatchExcerpt.lines(in: patch, side: .base, range: 13...13)
        #expect(lines.map(\.text) == ["let d = 5", "let d = 6"])
        #expect(lines.first?.oldNumber == 13)
    }

    @Test func linesOutsideTheHunksAreLeftOut() {
        #expect(PatchExcerpt.lines(in: patch, side: .head, range: 40...50).isEmpty)
    }
}

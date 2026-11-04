import Testing
@testable import RiviuDiff

struct StructuralChangeTests {
    private func kinds(base: String, head: String) -> [StructuralChange] {
        let file = FileDiff(path: "a.swift", status: .modified, baseLines: FileDiff.lines(of: base), headLines: FileDiff.lines(of: head))
        return StructuralChanges.classify(file).sorted { $0.key < $1.key }.map(\.value)
    }

    @Test func whitespaceAndLineBreaksAreFormatting() {
        #expect(kinds(base: "a\nlet x = f(1, 2)\nb", head: "a\nlet x = f(\n    1,\n    2\n)\nb") == [.formattingOnly])
    }

    @Test func consistentNameChangesAreRenames() {
        #expect(kinds(base: "a\nlet count = count + total\nb", head: "a\nlet size = size + total\nb") == [.renameOnly])
    }

    @Test func inconsistentNameChangesAreLogic() {
        #expect(kinds(base: "a\nf(x, x)\nb", head: "a\nf(y, z)\nb") == [.logic])
    }

    @Test func changedStringsAreNeverRenames() {
        #expect(kinds(base: "a\nprint(\"hello\")\nb", head: "a\nprint(\"goodbye\")\nb") == [.logic])
    }

    @Test func changedOperatorsAreLogic() {
        #expect(kinds(base: "a\nif x > 1 {\nb", head: "a\nif x >= 1 {\nb") == [.logic])
    }

    @Test func blocksRemovedAndAddedElsewhereAreMoved() {
        let base = "func a() {\n    let value = compute()\n    use(value)\n}\nfunc b() {}\nfunc c() {}"
        let head = "func b() {}\nfunc c() {}\nfunc a() {\n    let value = compute()\n    use(value)\n}"
        #expect(Set(kinds(base: base, head: head)) == [.moved])
    }
}

import Testing
@testable import RiviuDiff

struct NumberedPatchTests {
    @Test func numbersEachLineOnItsOwnSide() {
        let patch = """
        @@ -10,3 +10,3 @@ func refresh()
         let a = 1
        -let b = 2
        +let b = 3
         let c = 4
        """
        #expect(NumberedPatch.make(from: patch) == """
        @@ -10,3 +10,3 @@ func refresh()
          10 | let a = 1
        - 11 | let b = 2
        + 11 | let b = 3
          12 | let c = 4
        """)
    }

    @Test func restartsNumberingAtEachHunk() {
        let patch = """
        @@ -1 +1,2 @@
         first
        +second
        @@ -40,2 +41,1 @@
        -gone
         kept
        """
        #expect(NumberedPatch.make(from: patch) == """
        @@ -1 +1,2 @@
          1 | first
        + 2 | second
        @@ -40,2 +41,1 @@
        - 40 | gone
          41 | kept
        """)
    }

    @Test func keepsTheNoNewlineMarker() {
        let patch = "@@ -1 +1 @@\n-a\n\\ No newline at end of file\n+b"
        #expect(NumberedPatch.make(from: patch) == "@@ -1 +1 @@\n- 1 | a\n\\ No newline at end of file\n+ 1 | b")
    }
}

import Testing
@testable import RiviuAI

struct HotPathHopsTests {
    @Test func readsHopsWrappedInProse() throws {
        let reply = """
        Sure:
        ```json
        {"hops": [" Looks up the pending order by `id` ", "Marks it paid"]}
        ```
        """
        #expect(try HotPathHops.parse(reply).hops == ["Looks up the pending order by `id`", "Marks it paid"])
    }

    @Test func rejectsRepliesWithoutHops() {
        #expect(throws: ReviewReport.ParseError.self) { try HotPathHops.parse("No idea.") }
        #expect(throws: ReviewReport.ParseError.self) { try HotPathHops.parse(#"{"steps": []}"#) }
    }
}

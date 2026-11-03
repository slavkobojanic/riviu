import Testing
@testable import RiviuAI

struct ReviewReportTests {
    @Test func readsAReportWrappedInACodeFence() throws {
        let reply = """
        Here's the review:
        ```json
        {
          "summary": "Adds **caching**.",
          "risk": "medium",
          "findings": [
            {"file": "Sources/Cache.swift", "line": 12, "side": "new", "severity": "high",
             "title": "Cache never expires", "body": "Add a TTL."}
          ]
        }
        ```
        """
        let report = try ReviewReport.parse(reply)
        #expect(report.summary == "Adds **caching**.")
        #expect(report.risk == .medium)
        #expect(report.findings.count == 1)
        #expect(report.findings[0].file == "Sources/Cache.swift")
        #expect(report.findings[0].line == 12)
        #expect(report.findings[0].severity == .high)
    }

    @Test func sideDefaultsToTheNewFile() throws {
        let reply = #"{"summary": "s", "risk": "low", "findings": [{"file": "a", "line": 1, "severity": "low", "title": "t", "body": "b"}]}"#
        #expect(try ReviewReport.parse(reply).findings[0].side == .new)
    }

    @Test func rejectsRepliesWithoutJSON() {
        #expect(throws: ReviewReport.ParseError.self) { try ReviewReport.parse("I can't review this.") }
    }

    @Test func rejectsMissingFields() {
        #expect(throws: ReviewReport.ParseError.self) { try ReviewReport.parse(#"{"risk": "low", "findings": []}"#) }
    }
}

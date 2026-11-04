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

struct ReviewReportSuggestionTests {
    @Test func readsAnOptionalSuggestionAndEndLine() throws {
        let reply = #"{"summary": "s", "risk": "low", "findings": [{"file": "a", "line": 3, "endLine": 4, "severity": "low", "title": "t", "body": "b", "suggestion": "let x = 1"}]}"#
        let finding = try ReviewReport.parse(reply).findings[0]
        #expect(finding.endLine == 4)
        #expect(finding.suggestion == "let x = 1")
    }
}

struct ReviewReportSpecTests {
    @Test func readsSpecCheckAndQuestions() throws {
        let reply = """
        {"summary": "s", "risk": "low", "findings": [],
         "specCheck": {"goals": [{"goal": "Retry on 503", "status": "partial", "note": "No backoff."}], "unrequested": ["Renames Client"]},
         "questions": [{"file": "a.go", "line": 3, "question": "Why 5 retries?"}]}
        """
        let report = try ReviewReport.parse(reply)
        #expect(report.specCheck?.goals.first?.status == .partial)
        #expect(report.specCheck?.unrequested == ["Renames Client"])
        #expect(report.questions?.first?.line == 3)
    }

    @Test func olderRepliesWithoutThemStillParse() throws {
        let report = try ReviewReport.parse(#"{"summary": "s", "risk": "low", "findings": []}"#)
        #expect(report.specCheck == nil)
        #expect(report.questions == nil)
    }
}

struct ReviewReportReReviewTests {
    @Test func readsWhatHappenedToEarlierFindings() throws {
        let reply = #"{"summary": "s", "risk": "low", "findings": [], "previousFindings": [{"index": 0, "status": "addressed"}, {"index": 1, "status": "open", "line": 9}]}"#
        let previous = try #require(try ReviewReport.parse(reply).previousFindings)
        #expect(previous[0].status == .addressed)
        #expect(previous[1].line == 9)
    }
}

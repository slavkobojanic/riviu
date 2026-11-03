import Foundation
import Testing
@testable import RiviuGitHub

struct PullRequestQueryTests {
    @Test func defaultQueryFindsOpenReviewRequests() {
        #expect(PullRequestQuery().searchString == "is:pr archived:false review-requested:@me is:open")
    }

    @Test func includesRepositoryStateAndText() {
        var query = PullRequestQuery()
        query.involvement = .authored
        query.state = .merged
        query.repository = "apple/swift"
        query.text = " label:bug "
        #expect(query.searchString == "is:pr archived:false author:@me is:merged repo:apple/swift label:bug")
    }
}

struct GitHubDecodingTests {
    @Test func decodesSearchResults() throws {
        let json = """
        {"id": 1, "number": 42, "title": "Fix it", "state": "open", "draft": false, "comments": 3,
         "labels": [{"name": "bug", "color": "d73a4a"}], "updated_at": "2026-11-01T10:00:00Z",
         "repository_url": "https://api.github.com/repos/octo/app",
         "pull_request": {"merged_at": null},
         "user": {"login": "octocat", "avatar_url": "https://example.com/a.png"}}
        """
        let summary = try GitHubClient.decoder.decode(GitHubPullRequestSummary.self, from: Data(json.utf8))
        #expect(summary.repository == "octo/app")
        #expect(summary.user.login == "octocat")
        #expect(!summary.isMerged)
    }

    @Test func readsValidationErrors() {
        let body = #"{"message":"Unprocessable Entity","errors":["Can not approve your own pull request"]}"#
        #expect(GitHubClient.errorMessage(in: Data(body.utf8)) == "Unprocessable Entity: Can not approve your own pull request")
    }

    @Test func encodesMultiLineReviewComments() throws {
        let comment = GitHubReviewSubmission.Comment(path: "a.swift", body: "Hm", side: .right, lines: 3...5)
        let review = GitHubReviewSubmission(commitID: "abc", event: .comment, body: "", comments: [comment])
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(review), as: UTF8.self)
        #expect(json.contains(#""line":5"#))
        #expect(json.contains(#""start_line":3"#))
        #expect(json.contains(#""commit_id":"abc""#))
    }
}

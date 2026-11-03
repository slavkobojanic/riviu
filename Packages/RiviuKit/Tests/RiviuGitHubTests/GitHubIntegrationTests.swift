import Foundation
import Testing
@testable import RiviuGitHub

/// Reads from the real GitHub API with the GitHub CLI's token. Opt in with `RIVIU_INTEGRATION_TESTS=1 swift test`.
/// Read-only: it never writes to GitHub.
struct GitHubIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RIVIU_INTEGRATION_TESTS"] == "1"))
    func searchesAndLoadsAPullRequest() async throws {
        let client = GitHubClient(token: try await GitHubSignIn.tokenFromGitHubCLI())
        let user = try await client.currentUser()
        #expect(!user.login.isEmpty)

        var query = PullRequestQuery()
        query.involvement = .involved
        query.state = .all
        let results = try await client.searchPullRequests(query)
        print("Found \(results.count) pull requests for \(user.login)")

        guard let first = results.first else { return }
        let details = try await client.pullRequest(repository: first.repository, number: first.number)
        let files = try await client.changedFiles(repository: first.repository, number: first.number)
        let mergeBase = try await client.mergeBase(repository: first.repository, base: details.base.sha, head: details.head.sha)
        #expect(mergeBase.count == 40)
        print("\(first.repository)#\(first.number): \(files.count) files, head \(details.head.sha.prefix(7))")
        if let file = files.first(where: { $0.status != "removed" }) {
            let contents = try await client.fileContents(repository: first.repository, path: file.filename, ref: details.head.sha)
            #expect(!contents.isEmpty || file.additions == 0)
        }
    }
}

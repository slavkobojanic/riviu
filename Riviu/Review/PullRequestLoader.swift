import Foundation
import RiviuDiff
import RiviuGitHub

/// A file in the repository that tells AI tools how to work on it, like CLAUDE.md.
nonisolated struct RepositoryGuideline: Sendable {
    static let paths = ["CLAUDE.md", "AGENTS.md", ".github/copilot-instructions.md", ".cursorrules"]
    /// Each file is cut to this length so a long one can't crowd out the diff.
    static let maxCharacters = 8_000

    let path: String
    let text: String
}

/// Fetches pull requests and file contents from GitHub.
nonisolated struct PullRequestLoader: Sendable {
    enum LoadError: LocalizedError {
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "Sign in to GitHub to open this pull request."
            }
        }
    }

    /// nil when not signed in to GitHub.
    let client: GitHubClient?
    /// Riviu's clones, read before asking the API.
    let repositories: LocalRepositories

    func pullRequest(_ reference: PullRequestReference) async throws -> PullRequest {
        guard let client else { throw LoadError.notSignedIn }

        async let details = client.pullRequest(repository: reference.repository, number: reference.number)
        async let files = client.changedFiles(repository: reference.repository, number: reference.number)
        let pullRequest = try await details
        let mergeBase = try await mergeBase(of: pullRequest, reference: reference, client: client)

        return PullRequest(
            reference: reference,
            title: pullRequest.title,
            author: pullRequest.user.login,
            headBranch: pullRequest.head.ref,
            baseBranch: pullRequest.base.ref,
            summary: pullRequest.body ?? "",
            headSHA: pullRequest.head.sha,
            baseSHA: mergeBase,
            webURL: pullRequest.htmlUrl,
            files: try await files.map(Self.changedFile)
        )
    }

    /// From the local clone when it has both commits, otherwise from the API.
    private func mergeBase(of pullRequest: GitHubPullRequest, reference: PullRequestReference, client: GitHubClient) async throws -> String {
        let repository = reference.repository
        if await repositories.prepare(pullRequest, number: reference.number, repository: repository, client: client),
           let mergeBase = try? await repositories.mergeBase(of: pullRequest.base.sha, and: pullRequest.head.sha, in: repository) {
            return mergeBase
        }
        return try await client.mergeBase(repository: repository, base: pullRequest.base.sha, head: pullRequest.head.sha)
    }

    /// A file at a commit, from the local clone when it's there, otherwise from the API.
    private func fileContents(of path: String, at commit: String, in repository: String, client: GitHubClient) async throws -> Data {
        if let data = try? await repositories.contents(of: path, at: commit, in: repository, token: client.token) {
            return data
        }
        return try await client.fileContents(repository: repository, path: path, ref: commit)
    }

    /// Downloads both versions of a file and diffs them. `baseSHA` defaults to the pull request's base.
    func content(of file: ChangedFile, in pullRequest: PullRequest, baseSHA: String? = nil) async throws -> FileContent {
        guard let client else { throw LoadError.notSignedIn }
        let repository = pullRequest.reference.repository

        async let base = file.status == .added
            ? Data()
            : fileContents(of: file.previousPath ?? file.path, at: baseSHA ?? pullRequest.baseSHA, in: repository, client: client)
        async let head = file.status == .deleted
            ? Data()
            : fileContents(of: file.path, at: pullRequest.headSHA, in: repository, client: client)
        let (baseData, headData) = try await (base, head)

        if isBinary(baseData) || isBinary(headData) {
            return .binary
        }
        return .loaded(FileDiff(path: file.path, status: file.status,
                                baseLines: FileDiff.lines(of: text(baseData)),
                                headLines: FileDiff.lines(of: text(headData))))
    }

    /// The repository's instructions for AI tools, at the reviewed commit. Missing files are skipped.
    func repositoryGuidelines(for pullRequest: PullRequest) async -> [RepositoryGuideline] {
        guard let client else { return [] }
        var guidelines: [RepositoryGuideline] = []
        for path in RepositoryGuideline.paths {
            guard let data = try? await fileContents(of: path, at: pullRequest.headSHA, in: pullRequest.reference.repository,
                                                     client: client) else { continue }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                guidelines.append(RepositoryGuideline(path: path, text: String(text.prefix(RepositoryGuideline.maxCharacters))))
            }
        }
        return guidelines
    }

    /// Issues the description says it fixes ("Fixes #12"), up to three.
    func linkedIssues(for pullRequest: PullRequest) async -> [GitHubIssue] {
        guard let client else { return [] }
        let pattern = #/(?i)\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)/#
        let numbers = pullRequest.summary.matches(of: pattern).compactMap { Int($0.1) }
        var issues: [GitHubIssue] = []
        for number in Array(Set(numbers)).sorted().prefix(3) {
            if let issue = try? await client.issue(repository: pullRequest.reference.repository, number: number) {
                issues.append(issue)
            }
        }
        return issues
    }

    static func changedFile(_ file: GitHubChangedFile) -> ChangedFile {
        let status: ChangeStatus = switch file.status {
        case "added": .added
        case "removed": .deleted
        case "renamed": .renamed
        default: .modified
        }
        return ChangedFile(path: file.filename, previousPath: file.previousFilename, status: status,
                           additions: file.additions, deletions: file.deletions, patch: file.patch)
    }

    /// Text files don't contain zero bytes; binary files nearly always do near the start.
    private func isBinary(_ data: Data) -> Bool {
        data.prefix(8000).contains(0)
    }

    /// Decodes UTF-8 with Unix line endings, dropping the final newline so the line count matches the file's.
    private func text(_ data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasSuffix("\n") {
            text.removeLast()
        }
        return text
    }
}

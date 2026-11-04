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

/// Fetches pull requests and file contents, from GitHub or from the built-in demos.
nonisolated struct PullRequestLoader: Sendable {
    enum LoadError: LocalizedError {
        case notSignedIn
        case unknownDemo

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "Sign in to GitHub to open this pull request."
            case .unknownDemo: "That demo pull request doesn't exist."
            }
        }
    }

    /// nil when not signed in to GitHub.
    let client: GitHubClient?

    func pullRequest(_ reference: PullRequestReference) async throws -> PullRequest {
        if reference.isDemo {
            guard let demo = DemoPullRequests.pullRequest(number: reference.number) else { throw LoadError.unknownDemo }
            return demo
        }
        guard let client else { throw LoadError.notSignedIn }

        async let details = client.pullRequest(repository: reference.repository, number: reference.number)
        async let files = client.changedFiles(repository: reference.repository, number: reference.number)
        let pullRequest = try await details
        let mergeBase = try await client.mergeBase(repository: reference.repository, base: pullRequest.base.sha, head: pullRequest.head.sha)

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
            files: try await files.map(changedFile)
        )
    }

    /// Downloads both versions of a file and diffs them.
    func content(of file: ChangedFile, in pullRequest: PullRequest) async throws -> FileContent {
        if pullRequest.reference.isDemo {
            guard let diff = DemoPullRequests.fileDiff(at: file.path) else { return .failed("Missing demo file.") }
            return .loaded(diff)
        }
        guard let client else { throw LoadError.notSignedIn }
        let repository = pullRequest.reference.repository

        async let base = file.status == .added
            ? Data()
            : client.fileContents(repository: repository, path: file.previousPath ?? file.path, ref: pullRequest.baseSHA)
        async let head = file.status == .deleted
            ? Data()
            : client.fileContents(repository: repository, path: file.path, ref: pullRequest.headSHA)
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
        guard let client, !pullRequest.reference.isDemo else { return [] }
        var guidelines: [RepositoryGuideline] = []
        for path in RepositoryGuideline.paths {
            guard let data = try? await client.fileContents(repository: pullRequest.reference.repository, path: path,
                                                            ref: pullRequest.headSHA) else { continue }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                guidelines.append(RepositoryGuideline(path: path, text: String(text.prefix(RepositoryGuideline.maxCharacters))))
            }
        }
        return guidelines
    }

    /// Issues the description says it fixes ("Fixes #12"), up to three.
    func linkedIssues(for pullRequest: PullRequest) async -> [GitHubIssue] {
        guard let client, !pullRequest.reference.isDemo else { return [] }
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

    private func changedFile(_ file: GitHubChangedFile) -> ChangedFile {
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

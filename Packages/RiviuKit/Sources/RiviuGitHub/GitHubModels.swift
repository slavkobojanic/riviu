import Foundation

public struct GitHubUser: Decodable, Sendable, Hashable {
    public let login: String
    public let name: String?
    public let avatarUrl: URL?
}

public struct GitHubLabel: Decodable, Sendable, Hashable {
    public let name: String
    /// Hex without "#", e.g. "d73a4a".
    public let color: String
}

/// A pull request as returned by the search API, enough to show it in a list.
public struct GitHubPullRequestSummary: Decodable, Sendable, Identifiable, Hashable {
    public struct PullRequestLinks: Decodable, Sendable, Hashable {
        public let mergedAt: Date?
    }

    public let id: Int
    public let number: Int
    public let title: String
    public let user: GitHubUser
    public let state: String
    public let draft: Bool?
    public let comments: Int
    public let labels: [GitHubLabel]
    public let updatedAt: Date
    public let repositoryUrl: URL
    public let pullRequest: PullRequestLinks?

    /// "owner/name", taken from the end of `repositoryUrl`.
    public var repository: String {
        repositoryUrl.pathComponents.suffix(2).joined(separator: "/")
    }

    public var isMerged: Bool { pullRequest?.mergedAt != nil }
    public var isDraft: Bool { draft ?? false }
}

/// The full details of one pull request.
public struct GitHubPullRequest: Decodable, Sendable {
    public struct Branch: Decodable, Sendable {
        public let ref: String
        public let sha: String
    }

    public let number: Int
    public let title: String
    public let body: String?
    public let user: GitHubUser
    public let head: Branch
    public let base: Branch
    public let htmlUrl: URL
    public let state: String
    public let draft: Bool?
    public let mergedAt: Date?
}

/// One file changed by a pull request.
public struct GitHubChangedFile: Decodable, Sendable {
    public let filename: String
    public let previousFilename: String?
    /// added, removed, modified, renamed, copied, changed or unchanged.
    public let status: String
    public let additions: Int
    public let deletions: Int
    /// The unified diff of the file, missing for binary or very large files.
    public let patch: String?
}

/// A review to submit, with its line comments.
public struct GitHubReviewSubmission: Encodable, Sendable {
    public enum Event: String, Encodable, Sendable, CaseIterable {
        case comment = "COMMENT"
        case approve = "APPROVE"
        case requestChanges = "REQUEST_CHANGES"
    }

    public struct Comment: Encodable, Sendable {
        /// "LEFT" is the base version, "RIGHT" the head version.
        public enum Side: String, Encodable, Sendable {
            case left = "LEFT"
            case right = "RIGHT"
        }

        public let path: String
        public let body: String
        /// 1-based line number of the last line the comment is on.
        public let line: Int
        public let side: Side
        /// Set for comments that span several lines.
        public let startLine: Int?
        public let startSide: Side?

        public init(path: String, body: String, side: Side, lines: ClosedRange<Int>) {
            self.path = path
            self.body = body
            self.side = side
            line = lines.upperBound
            startLine = lines.count > 1 ? lines.lowerBound : nil
            startSide = lines.count > 1 ? side : nil
        }
    }

    public let commitId: String
    public let event: Event
    public let body: String
    public let comments: [Comment]

    public init(commitID: String, event: Event, body: String, comments: [Comment]) {
        commitId = commitID
        self.event = event
        self.body = body
        self.comments = comments
    }
}

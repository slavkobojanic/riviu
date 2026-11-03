import Foundation
import RiviuDiff

/// Identifies a pull request: "owner/name#123", or "demo#482" for the built-in examples.
nonisolated struct PullRequestReference: Hashable, Codable, Sendable {
    static let demoRepository = "demo"

    let repository: String
    let number: Int

    var id: String { "\(repository)#\(number)" }
    var isDemo: Bool { repository == Self.demoRepository }
}

/// One file changed by a pull request. Its contents are loaded separately, when it's opened.
nonisolated struct ChangedFile: Identifiable, Sendable {
    let path: String
    /// The old path of a renamed file.
    let previousPath: String?
    let status: ChangeStatus
    let additions: Int
    let deletions: Int
    /// The unified diff, used to give the AI context. Missing for binary and very large files.
    let patch: String?

    var id: String { path }
    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

nonisolated struct PullRequest: Identifiable, Sendable {
    let reference: PullRequestReference
    let title: String
    let author: String
    let headBranch: String
    let baseBranch: String
    let summary: String
    /// The commit being reviewed.
    let headSHA: String
    /// The commit the changes are measured from.
    let baseSHA: String
    let webURL: URL?
    let files: [ChangedFile]

    var id: String { reference.id }
    var number: Int { reference.number }
    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }

    func file(at path: String) -> ChangedFile? {
        files.first { $0.path == path }
    }
}

/// What the diff area shows for a file.
nonisolated enum FileContent: Sendable {
    case loading
    case loaded(FileDiff)
    case binary
    case failed(String)
}

/// An issue the AI review found, pinned to a line.
nonisolated struct ReviewFinding: Identifiable, Sendable, Codable {
    enum Severity: String, Sendable, Codable, Comparable {
        case high = "High"
        case medium = "Medium"
        case low = "Low"

        /// High sorts first.
        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rank < rhs.rank
        }

        private var rank: Int {
            switch self {
            case .high: 0
            case .medium: 1
            case .low: 2
            }
        }
    }

    let id: String
    let filePath: String
    let side: DiffSide
    let lineIndex: Int
    let title: String
    let body: String
    let severity: Severity
}

/// A review comment the user is writing or has written, on one or more lines.
nonisolated struct ReviewComment: Identifiable, Sendable {
    let id: UUID
    let pullRequest: PullRequestReference
    let filePath: String
    let side: DiffSide
    let lines: ClosedRange<Int>
    /// The code the comment is about, used for "Suggest change".
    let code: String
    var body: String
    var isEditing: Bool
    /// True until the comment is added for the first time; cancelling a new comment deletes it.
    var isNew: Bool
    /// True once it has been posted to GitHub as part of a review.
    var isSubmitted = false

    var lineLabel: String { describeLines(lines, on: side) }
    var isPending: Bool { !isNew && !isEditing && !isSubmitted }
}

/// A span of code picked in the diff, by selecting it or hovering its gutter.
nonisolated struct CodeTarget: Sendable {
    let filePath: String
    let side: DiffSide
    let lines: ClosedRange<Int>
    let code: String

    var label: String { describeLines(lines, on: side) }
}

/// "line 12", "lines 12–18", or "base line 12" for the old version of the file.
nonisolated func describeLines(_ lines: ClosedRange<Int>, on side: DiffSide) -> String {
    let prefix = side == .base ? "base " : ""
    if lines.count == 1 {
        return "\(prefix)line \(lines.lowerBound + 1)"
    }
    return "\(prefix)lines \(lines.lowerBound + 1)–\(lines.upperBound + 1)"
}

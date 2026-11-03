import Foundation
import RiviuDiff

nonisolated struct PullRequest: Identifiable, Sendable {
    let number: Int
    let title: String
    let author: String
    let branch: String
    let summary: String
    let files: [FileDiff]

    var id: Int { number }
    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }

    func file(at path: String) -> FileDiff? {
        files.first { $0.path == path }
    }
}

/// An issue the AI review found, pinned to a line.
nonisolated struct ReviewFinding: Identifiable, Sendable {
    enum Severity: String {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
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
    let pullRequestNumber: Int
    let filePath: String
    let side: DiffSide
    let lines: ClosedRange<Int>
    /// The code the comment is about, used for "Suggest change".
    let code: String
    var body: String
    var isEditing: Bool
    /// True until the comment is added for the first time; cancelling a new comment deletes it.
    var isNew: Bool

    var lineLabel: String { describeLines(lines, on: side) }
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

import Foundation

/// Which version of a file a line belongs to: the pull request's base or its head.
public enum DiffSide: Int, Sendable, Hashable, Codable {
    case base = 0
    case head = 1
}

public enum ChangeStatus: Sendable, Hashable {
    case modified
    case added
    case deleted
}

/// A run of lines that is either identical on both sides or changed between them.
/// Ranges are line indexes into `FileDiff.baseLines` / `FileDiff.headLines`.
public enum DiffSegment: Sendable, Equatable {
    case unchanged(base: Range<Int>, head: Range<Int>)
    case changed(removed: Range<Int>, added: Range<Int>)
}

/// One file in a pull request, with both versions and the line diff between them.
public struct FileDiff: Identifiable, Sendable {
    public let path: String
    public let status: ChangeStatus
    public let baseLines: [String]
    public let headLines: [String]
    public let segments: [DiffSegment]
    public let additions: Int
    public let deletions: Int

    public var id: String { path }
    public var fileName: String { (path as NSString).lastPathComponent }
    public var directory: String { (path as NSString).deletingLastPathComponent }

    public init(path: String, status: ChangeStatus, baseLines: [String], headLines: [String]) {
        self.path = path
        self.status = status
        self.baseLines = baseLines
        self.headLines = headLines
        segments = LineDiff.segments(base: baseLines, head: headLines)

        var additions = 0
        var deletions = 0
        for case let .changed(removed, added) in segments {
            additions += added.count
            deletions += removed.count
        }
        self.additions = additions
        self.deletions = deletions
    }

    public func lines(on side: DiffSide) -> [String] {
        side == .base ? baseLines : headLines
    }

    /// Splits file contents into lines. An empty file has no lines.
    public static func lines(of text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: "\n")
    }
}

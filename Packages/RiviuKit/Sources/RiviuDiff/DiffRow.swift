public enum DiffLayout: String, CaseIterable, Sendable, Codable {
    case unified
    case split
}

/// One line of code as shown in the diff.
public struct DiffLine: Sendable, Equatable {
    public enum Kind: Sendable {
        case unchanged
        case removed
        case added
    }

    public let side: DiffSide
    /// 0-based index into that side's lines.
    public let index: Int
    public let text: String
    public let kind: Kind
    /// UTF-16 range of the words that changed within the line, if worth highlighting.
    public let changedRange: Range<Int>?
    /// Set on changed lines that are only moved, renamed or reformatted; those are drawn dimmed.
    public let cosmeticChange: StructuralChange?
    /// True for the first line of its side of a hunk, where the hunk's label is drawn.
    public let startsChange: Bool

    public var number: Int { index + 1 }

    public init(side: DiffSide, index: Int, text: String, kind: Kind, changedRange: Range<Int>? = nil,
                cosmeticChange: StructuralChange? = nil, startsChange: Bool = false) {
        self.side = side
        self.index = index
        self.text = text
        self.kind = kind
        self.changedRange = changedRange
        self.cosmeticChange = cosmeticChange
        self.startsChange = startsChange
    }
}

/// Identifies something shown between diff lines, such as a comment thread or an AI finding.
public struct AttachmentID: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Places an attachment directly below a line.
public struct Attachment: Sendable {
    public let id: AttachmentID
    public let side: DiffSide
    public let lineIndex: Int

    public init(id: AttachmentID, side: DiffSide, lineIndex: Int) {
        self.id = id
        self.side = side
        self.lineIndex = lineIndex
    }
}

/// One row of the diff view. Both columns of the split view read from the same rows,
/// which is what keeps them aligned.
public enum DiffRow: Sendable {
    /// Split view: base on the left, head on the right. `nil` means a blank filler cell.
    case split(base: DiffLine?, head: DiffLine?)
    /// Unified view: a single line, with its line index on each side it exists on.
    case unified(DiffLine, baseIndex: Int?, headIndex: Int?)
    /// A run of lines hidden until expanded: unchanged lines, or a cosmetic change when `change` is set.
    case collapsed(segmentIndex: Int, hiddenLineCount: Int, change: StructuralChange?)
    case attachment(AttachmentID, side: DiffSide)

    /// The base and head line indexes shown in this row, or nil for rows that show no code.
    public var lineIndices: (base: Int?, head: Int?)? {
        switch self {
        case let .split(base, head): (base?.index, head?.index)
        case let .unified(_, baseIndex, headIndex): (baseIndex, headIndex)
        case .collapsed, .attachment: nil
        }
    }
}

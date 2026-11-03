public struct DiffRowOptions: Sendable {
    public var layout: DiffLayout = .split
    /// Unchanged lines kept visible around each change.
    public var contextLines = 3
    /// Unchanged segments the user expanded (indexes into `FileDiff.segments`).
    public var expandedSegments: Set<Int> = []
    public var expandAll = false
    public var highlightsWordChanges = true

    public init() {}
}

/// Turns a file diff into the rows the diff view draws.
public enum DiffRowBuilder {
    public static func rows(for file: FileDiff, options: DiffRowOptions, attachments: [Attachment] = []) -> [DiffRow] {
        var options = options
        options.expandedSegments.formUnion(segmentsContaining(attachments, in: file))

        var rows: [DiffRow] = []
        let lastSegment = file.segments.count - 1
        for (index, segment) in file.segments.enumerated() {
            switch segment {
            case let .unchanged(base, head):
                rows += unchangedRows(file: file, segmentIndex: index, base: base, head: head,
                                      isFirst: index == 0, isLast: index == lastSegment, options: options)
            case let .changed(removed, added):
                rows += changedRows(file: file, removed: removed, added: added, options: options)
            }
        }
        return insert(attachments, into: rows)
    }

    // MARK: - Unchanged lines

    private static func unchangedRows(file: FileDiff, segmentIndex: Int, base: Range<Int>, head: Range<Int>,
                                      isFirst: Bool, isLast: Bool, options: DiffRowOptions) -> [DiffRow] {
        let count = base.count
        let leading = isFirst ? 0 : options.contextLines
        let trailing = isLast ? 0 : options.contextLines
        let showAll = options.expandAll || options.expandedSegments.contains(segmentIndex) || count <= leading + trailing + 1

        func row(_ offset: Int) -> DiffRow {
            unchangedRow(file: file, baseIndex: base.lowerBound + offset, headIndex: head.lowerBound + offset, layout: options.layout)
        }

        if showAll {
            return (0..<count).map(row)
        }
        let hidden = count - leading - trailing
        return (0..<leading).map(row)
            + [.collapsed(segmentIndex: segmentIndex, hiddenLineCount: hidden)]
            + ((count - trailing)..<count).map(row)
    }

    private static func unchangedRow(file: FileDiff, baseIndex: Int, headIndex: Int, layout: DiffLayout) -> DiffRow {
        let headLine = DiffLine(side: .head, index: headIndex, text: file.headLines[headIndex], kind: .unchanged)
        switch layout {
        case .split:
            let baseLine = DiffLine(side: .base, index: baseIndex, text: file.baseLines[baseIndex], kind: .unchanged)
            return .split(base: baseLine, head: headLine)
        case .unified:
            return .unified(headLine, baseIndex: baseIndex, headIndex: headIndex)
        }
    }

    // MARK: - Changed lines

    private static func changedRows(file: FileDiff, removed: Range<Int>, added: Range<Int>, options: DiffRowOptions) -> [DiffRow] {
        // Removed and added lines are paired up in order; pairs get word-level highlights.
        let pairCount = min(removed.count, added.count)
        var removedLines: [DiffLine] = []
        var addedLines: [DiffLine] = []

        for offset in 0..<removed.count {
            let index = removed.lowerBound + offset
            var changed: Range<Int>?
            if options.highlightsWordChanges && offset < pairCount {
                changed = WordChange.changedRanges(old: file.baseLines[index], new: file.headLines[added.lowerBound + offset])?.old
            }
            removedLines.append(DiffLine(side: .base, index: index, text: file.baseLines[index], kind: .removed, changedRange: changed))
        }
        for offset in 0..<added.count {
            let index = added.lowerBound + offset
            var changed: Range<Int>?
            if options.highlightsWordChanges && offset < pairCount {
                changed = WordChange.changedRanges(old: file.baseLines[removed.lowerBound + offset], new: file.headLines[index])?.new
            }
            addedLines.append(DiffLine(side: .head, index: index, text: file.headLines[index], kind: .added, changedRange: changed))
        }

        switch options.layout {
        case .split:
            let rowCount = max(removedLines.count, addedLines.count)
            return (0..<rowCount).map { i in
                .split(base: i < removedLines.count ? removedLines[i] : nil,
                       head: i < addedLines.count ? addedLines[i] : nil)
            }
        case .unified:
            return removedLines.map { .unified($0, baseIndex: $0.index, headIndex: nil) }
                + addedLines.map { .unified($0, baseIndex: nil, headIndex: $0.index) }
        }
    }

    // MARK: - Attachments

    /// Unchanged segments that must be expanded so every attachment has a visible line to sit under.
    private static func segmentsContaining(_ attachments: [Attachment], in file: FileDiff) -> Set<Int> {
        var result = Set<Int>()
        for attachment in attachments {
            for (index, segment) in file.segments.enumerated() {
                guard case let .unchanged(base, head) = segment else { continue }
                let range = attachment.side == .base ? base : head
                if range.contains(attachment.lineIndex) {
                    result.insert(index)
                }
            }
        }
        return result
    }

    private static func insert(_ attachments: [Attachment], into rows: [DiffRow]) -> [DiffRow] {
        guard !attachments.isEmpty else { return rows }
        var result: [DiffRow] = []
        for row in rows {
            result.append(row)
            guard let indices = row.lineIndices else { continue }
            for attachment in attachments where attachment.side == .base && attachment.lineIndex == indices.base {
                result.append(.attachment(attachment.id, side: .base))
            }
            for attachment in attachments where attachment.side == .head && attachment.lineIndex == indices.head {
                result.append(.attachment(attachment.id, side: .head))
            }
        }
        return result
    }
}

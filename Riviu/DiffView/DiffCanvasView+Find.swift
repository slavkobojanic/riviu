import AppKit
import RiviuDiff

struct FindMatch: Equatable {
    let row: Int
    let column: Int
    let range: NSRange
}

/// Find in file: every match is highlighted and the current one is scrolled into view.
extension DiffCanvasView {
    func setFindQuery(_ query: String) {
        guard query != findQuery else { return }
        findQuery = query
        updateFindMatches(revealCurrent: true)
    }

    func moveToFindMatch(forward: Bool) {
        guard !findMatches.isEmpty else {
            NSSound.beep()
            return
        }
        currentMatchIndex = (currentMatchIndex + (forward ? 1 : -1) + findMatches.count) % findMatches.count
        revealCurrentMatch()
        reportFindStatus()
        setNeedsDisplay(visibleRect)
    }

    func updateFindMatches(revealCurrent: Bool) {
        let previousMatch = findMatches.indices.contains(currentMatchIndex) ? findMatches[currentMatchIndex] : nil
        findMatches = findQuery.isEmpty ? [] : allMatches()
        if let previousMatch, let index = findMatches.firstIndex(of: previousMatch) {
            currentMatchIndex = index
        } else {
            let firstVisibleRow = visibleRows.first ?? 0
            currentMatchIndex = findMatches.firstIndex { $0.row >= firstVisibleRow } ?? (findMatches.isEmpty ? -1 : 0)
        }
        if revealCurrent {
            revealCurrentMatch()
        }
        reportFindStatus()
        setNeedsDisplay(visibleRect)
    }

    private func allMatches() -> [FindMatch] {
        var matches: [FindMatch] = []
        for row in rows.indices {
            for column in 0...1 {
                guard let line = line(atRow: row, column: column) else { continue }
                // In the split view an unchanged line shows on both sides; count it once, on the right.
                if layout == .split && column == 0 && line.kind == .unchanged { continue }
                for range in ranges(of: findQuery, in: line.text) {
                    matches.append(FindMatch(row: row, column: column, range: range))
                }
            }
        }
        return matches
    }

    private func ranges(of query: String, in text: String) -> [NSRange] {
        let text = text as NSString
        var ranges: [NSRange] = []
        var searchStart = 0
        while searchStart < text.length {
            let found = text.range(of: query, options: .caseInsensitive,
                                   range: NSRange(location: searchStart, length: text.length - searchStart))
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            searchStart = found.location + max(1, found.length)
        }
        return ranges
    }

    private func revealCurrentMatch() {
        guard findMatches.indices.contains(currentMatchIndex) else { return }
        let match = findMatches[currentMatchIndex]
        revealRow(match.row, margin: 60)
        guard let line = line(atRow: match.row, column: match.column) else { return }
        let textLine = cachedTextLine(for: line, row: match.row, column: match.column)
        revealTextRange(from: CTLineGetOffsetForStringIndex(textLine, match.range.location, nil),
                        to: CTLineGetOffsetForStringIndex(textLine, NSMaxRange(match.range), nil))
    }

    private func reportFindStatus() {
        let status = FindStatus(current: currentMatchIndex, total: findMatches.count)
        Task { @MainActor in self.onFindStatus?(status) }
    }

    /// Drawn for every visible line, so both copies of an unchanged line in the split view get highlighted.
    func drawFindMatches(in line: DiffLine, row: Int, column: Int, textLine: CTLine, textX: CGFloat, codeArea: CGRect,
                         context: CGContext) {
        guard !findQuery.isEmpty else { return }
        let current = findMatches.indices.contains(currentMatchIndex) ? findMatches[currentMatchIndex] : nil
        for range in ranges(of: findQuery, in: line.text) {
            let start = CTLineGetOffsetForStringIndex(textLine, range.location, nil)
            let end = CTLineGetOffsetForStringIndex(textLine, NSMaxRange(range), nil)
            let isCurrent = current == FindMatch(row: row, column: column, range: range)
            context.setFillColor(isCurrent ? palette.currentFindMatch : palette.findMatch)
            let highlight = CGRect(x: textX + start - 1, y: codeArea.minY + 2, width: end - start + 2, height: codeArea.height - 4)
            context.addPath(CGPath(roundedRect: highlight, cornerWidth: 3, cornerHeight: 3, transform: nil))
            context.fillPath()
        }
    }
}

import AppKit
import RiviuDiff
import RiviuSyntax

/// Hovering the gutter highlights the block of code under the mouse and shows the AI and comment buttons.
extension DiffCanvasView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate]
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isInGutter(point) {
            NSCursor.arrow.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        cursorUpdate(with: event)
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        if !popover.isShown {
            setHover(nil)
        }
    }

    func updateHoverForCurrentMouseLocation() {
        guard let window, !popover.isShown else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if visibleRect.contains(point) {
            updateHover(at: point)
        } else {
            setHover(nil)
        }
    }

    private func updateHover(at point: CGPoint) {
        guard !popover.isShown, !isDraggingSelection else { return }
        if let selection, !selection.isCaret { return } // the buttons stay next to the selection

        let column = column(atX: point.x)
        guard isInGutter(point), let row = rowIndex(atY: point.y), line(atRow: row, column: column) != nil else {
            setHover(nil)
            return
        }
        if let hover, hover.row == row, hover.column == column { return }
        setHover(GutterHover(row: row, column: column, block: block(containingRow: row, column: column)))
    }

    private func setHover(_ newHover: GutterHover?) {
        if hover == nil && newHover == nil { return }
        hover = newHover
        setNeedsDisplay(visibleRect)
        placeGutterActions()
    }

    // MARK: - Blocks

    /// A changed line belongs to its run of changed lines. An unchanged line belongs to the smallest
    /// statement, call or declaration around it that spans several lines.
    func block(containingRow row: Int, column: Int) -> ClosedRange<Int> {
        guard let line = line(atRow: row, column: column) else { return row...row }
        if line.kind != .unchanged {
            return changedRun(around: row)
        }
        guard let lines = syntax(for: line.side)?.enclosingBlock(line: line.index) else { return row...row }
        return rowsShowing(lines: lines, on: line.side, column: column, around: row)
    }

    private func changedRun(around row: Int) -> ClosedRange<Int> {
        func isChanged(_ index: Int) -> Bool? {
            switch rows[index] {
            case let .split(base, head): return !(base?.kind == .unchanged && head?.kind == .unchanged)
            case let .unified(line, _, _): return line.kind != .unchanged
            case .attachment: return nil // skip over comments inside a change
            case .collapsed: return false
            }
        }
        var first = row
        var index = row - 1
        while index >= 0, isChanged(index) != false {
            if isChanged(index) == true { first = index }
            index -= 1
        }
        var last = row
        index = row + 1
        while index < rows.count, isChanged(index) != false {
            if isChanged(index) == true { last = index }
            index += 1
        }
        return first...last
    }

    private func rowsShowing(lines: ClosedRange<Int>, on side: DiffSide, column: Int, around row: Int) -> ClosedRange<Int> {
        func furthestRow(step: Int) -> Int {
            var furthest = row
            var index = row + step
            while rows.indices.contains(index) {
                if case .collapsed = rows[index] { break }
                if let other = line(atRow: index, column: column), other.side == side {
                    guard lines.contains(other.index) else { break }
                    furthest = index
                }
                index += step
            }
            return furthest
        }
        return furthestRow(step: -1)...furthestRow(step: 1)
    }

    // MARK: - The AI and comment buttons

    func placeGutterActions() {
        let anchorRow: Int
        let column: Int
        if let selection, !selection.isCaret, !isDraggingSelection {
            anchorRow = selection.end.row
            column = selection.column
        } else if let hover {
            anchorRow = hover.row
            column = hover.column
        } else {
            gutterActions.isHidden = true
            return
        }
        guard anchorRow + 1 < rowTops.count else {
            gutterActions.isHidden = true
            return
        }
        let size = gutterActionsSize
        let x = max(columnX(column) + 2, columnX(column) + gutterWidth - size.width - 4)
        gutterActions.frame = CGRect(x: x, y: rowTops[anchorRow] + (lineHeight - size.height) / 2, width: size.width, height: size.height)
        gutterActions.isHidden = false
    }

    /// What the buttons act on: the selection if there is one, otherwise the hovered block.
    func currentTarget() -> CodeTarget? {
        let column: Int
        let rowRange: ClosedRange<Int>
        if let selection, !selection.isCaret {
            column = selection.column
            rowRange = selection.start.row...selection.end.row
        } else if let hover {
            column = hover.column
            rowRange = hover.block
        } else {
            return nil
        }

        let lines = rowRange.compactMap { line(atRow: $0, column: column) }
        // In the unified view a block can mix removed (base) and added (head) lines; comments go on the head side.
        let side: DiffSide = lines.contains { $0.side == .head } ? .head : .base
        let indexes = lines.filter { $0.side == side }.map(\.index)
        guard let first = indexes.min(), let last = indexes.max() else { return nil }

        let code: String
        if let selection, !selection.isCaret, !selection.selectsWholeLines, let text = selectedText() {
            code = text
        } else if layout == .unified {
            code = lines.map { line in
                switch line.kind {
                case .added: "+ " + line.text
                case .removed: "- " + line.text
                case .unchanged: "  " + line.text
                }
            }.joined(separator: "\n")
        } else {
            code = lines.map(\.text).joined(separator: "\n")
        }
        return CodeTarget(filePath: filePath, side: side, lines: first...last, code: code)
    }

    func explainTarget() {
        guard let target = currentTarget(), let content = makeExplainPopover?(target) else { return }
        popover.contentViewController = content
        popover.show(relativeTo: gutterActions.bounds, of: gutterActions, preferredEdge: .maxY)
    }

    func commentOnTarget() {
        guard let target = currentTarget() else { return }
        clearInteraction()
        needsDisplay = true
        onComment?(target)
    }
}

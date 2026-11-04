import AppKit
import RiviuDiff

/// Mouse selection and copying.
extension DiffCanvasView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if let row = rowIndex(atY: point.y), case let .collapsed(segmentIndex, _, _) = rows[row] {
            onExpandSegment?(segmentIndex)
            return
        }

        if popover.isShown {
            popover.close()
        }
        hover = nil
        caretGoalX = nil
        let column = column(atX: point.x)
        guard let position = textPosition(at: point, column: column) else {
            selection = nil
            placeGutterActions()
            needsDisplay = true
            return
        }
        if event.modifierFlags.contains(.command), !isInGutter(point), goToDefinition(at: position, column: column, point: point) {
            return
        }

        selection = selectionForClick(event, at: position, column: column, inGutter: isInGutter(point))
        gutterActions.isHidden = true
        setNeedsDisplay(visibleRect)
        trackDrag(column: column, startedInGutter: isInGutter(point))
        placeGutterActions()
        setNeedsDisplay(visibleRect)
        NSAccessibility.post(element: self, notification: .selectedTextChanged)
    }

    private func selectionForClick(_ event: NSEvent, at position: TextPosition, column: Int, inGutter: Bool) -> DiffSelection {
        if inGutter || event.clickCount >= 3 {
            return DiffSelection(column: column, anchor: position, head: position, selectsWholeLines: true)
        }
        if event.modifierFlags.contains(.shift), var extended = selection, extended.column == column {
            extended.head = position
            return extended
        }
        if event.clickCount == 2, let line = line(atRow: position.row, column: column) {
            let word = wordRange(in: line.text, around: position.column)
            return DiffSelection(column: column, anchor: TextPosition(row: position.row, column: word.lowerBound),
                                 head: TextPosition(row: position.row, column: word.upperBound))
        }
        return .caret(at: position, column: column)
    }

    /// Follows the mouse until it's released, scrolling when it reaches an edge.
    private func trackDrag(column: Int, startedInGutter: Bool) {
        isDraggingSelection = true
        defer { isDraggingSelection = false }

        while let event = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), event.type == .leftMouseDragged {
            autoscroll(with: event)
            let point = convert(event.locationInWindow, from: nil)
            let rightEdge = columnX(column) + columnWidth(column)
            let leftEdge = columnX(column) + gutterWidth
            if point.x > rightEdge - 10 {
                scrollHorizontally(by: -12)
            } else if point.x < leftEdge && !startedInGutter {
                scrollHorizontally(by: 12)
            }
            if var current = selection, let position = textPosition(at: point, column: column) {
                current.head = position
                selection = current
                setNeedsDisplay(visibleRect)
            }
        }
    }

    /// The text position under a point, snapping to the nearest row that has code in this column.
    func textPosition(at point: CGPoint, column: Int) -> TextPosition? {
        guard !rows.isEmpty else { return nil }
        let y = min(max(point.y, 0), rowTops[rows.count] - 1)
        guard let rowUnderPoint = rowIndex(atY: y), let row = nearestRowWithCode(to: rowUnderPoint, column: column) else { return nil }
        return TextPosition(row: row, column: textColumn(atX: point.x - textOriginX(column), row: row, column: column))
    }

    private func nearestRowWithCode(to row: Int, column: Int) -> Int? {
        if line(atRow: row, column: column) != nil { return row }
        for distance in 1..<400 {
            if line(atRow: row + distance, column: column) != nil { return row + distance }
            if line(atRow: row - distance, column: column) != nil { return row - distance }
        }
        return nil
    }

    /// The UTF-16 offset in a row's text closest to an x position measured from the start of the text.
    func textColumn(atX x: CGFloat, row: Int, column: Int) -> Int {
        guard let line = line(atRow: row, column: column), x > 0 else { return 0 }
        let index = CTLineGetStringIndexForPosition(cachedTextLine(for: line, row: row, column: column), CGPoint(x: x, y: 0))
        let length = line.text.utf16.count
        return index == kCFNotFound ? length : min(max(0, index), length)
    }

    /// The x offset of a text position from the start of its row's text.
    func xOffset(of position: TextPosition, column: Int) -> CGFloat {
        guard let line = line(atRow: position.row, column: column) else { return 0 }
        let textLine = cachedTextLine(for: line, row: position.row, column: column)
        return CTLineGetOffsetForStringIndex(textLine, min(position.column, line.text.utf16.count), nil)
    }

    func isWordCharacter(_ character: UInt16) -> Bool {
        (48...57).contains(character) || (65...90).contains(character) || (97...122).contains(character) || character == 95
    }

    /// ⌘-click on a name shows where it's defined. Returns false when there's no name under the click.
    private func goToDefinition(at position: TextPosition, column: Int, point: CGPoint) -> Bool {
        guard let line = line(atRow: position.row, column: column) else { return false }
        let range = wordRange(in: line.text, around: position.column)
        let characters = Array(line.text.utf16)
        guard !range.isEmpty else { return false }
        let name = String(decoding: characters[range], as: UTF16.self)
        guard !(name.first?.isNumber ?? true) else { return false }
        let target = CodeTarget(filePath: filePath, side: line.side, lines: line.index...line.index, code: line.text)
        selection = DiffSelection(column: column, anchor: TextPosition(row: position.row, column: range.lowerBound),
                                  head: TextPosition(row: position.row, column: range.upperBound))
        setNeedsDisplay(visibleRect)
        if let content = goToDefinition?(name, target) {
            popover.contentViewController = content
            popover.show(relativeTo: CGRect(x: point.x, y: rowTops[position.row], width: 1, height: lineHeight), of: self, preferredEdge: .maxY)
        }
        return true
    }

    private func wordRange(in text: String, around offset: Int) -> Range<Int> {
        let characters = Array(text.utf16)
        var start = min(offset, characters.count)
        var end = start
        while start > 0 && isWordCharacter(characters[start - 1]) { start -= 1 }
        while end < characters.count && isWordCharacter(characters[end]) { end += 1 }
        return start..<end
    }

    func lineLength(atRow row: Int, column: Int) -> Int {
        line(atRow: row, column: column)?.text.utf16.count ?? 0
    }

    // MARK: - Copy

    func selectedText() -> String? {
        guard let selection, !selection.isCaret else { return nil }
        var lines: [String] = []
        for row in selection.start.row...selection.end.row {
            guard let line = line(atRow: row, column: selection.column) else { continue }
            let text = line.text as NSString
            var start = 0
            var end = text.length
            if !selection.selectsWholeLines {
                if row == selection.start.row { start = min(selection.start.column, text.length) }
                if row == selection.end.row { end = min(selection.end.column, text.length) }
            }
            lines.append(text.substring(with: NSRange(location: start, length: max(0, end - start))))
        }
        return lines.joined(separator: "\n")
    }

    @objc func copy(_ sender: Any?) {
        guard let text = selectedText() else {
            NSSound.beep()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    override func selectAll(_ sender: Any?) {
        let column = selection?.column ?? (layout == .split ? 1 : 0)
        guard let first = rows.indices.first(where: { line(atRow: $0, column: column) != nil }),
              let last = rows.indices.last(where: { line(atRow: $0, column: column) != nil }) else { return }
        selection = DiffSelection(column: column, anchor: TextPosition(row: first, column: 0),
                                  head: TextPosition(row: last, column: lineLength(atRow: last, column: column)))
        hover = nil
        placeGutterActions()
        setNeedsDisplay(visibleRect)
    }
}

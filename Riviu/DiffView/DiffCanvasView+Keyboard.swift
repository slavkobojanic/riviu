import AppKit
import RiviuDiff

/// Moving the caret and extending the selection with the keyboard.
///
/// AppKit turns key presses into standard commands (`moveLeft:`, `moveWordRightAndModifySelection:`, …)
/// based on the user's key bindings; each override below moves the caret one way.
extension DiffCanvasView {
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            collapseOrClearSelection()
        } else {
            interpretKeyEvents([event])
        }
    }

    /// The diff is read-only, so typed characters are ignored.
    override func insertText(_ insertString: Any) {}

    override func doCommand(by selector: Selector) {
        if responds(to: selector) {
            perform(selector, with: nil)
        } else {
            super.doCommand(by: selector)
        }
    }

    private func collapseOrClearSelection() {
        if let current = selection, !current.isCaret {
            selection = .caret(at: current.head, column: current.column)
        } else {
            selection = nil
        }
        placeGutterActions()
        setNeedsDisplay(visibleRect)
    }

    // MARK: - Moving

    /// Moves the caret (or the selection's moving end, when `extend` is true) to wherever `destination` says.
    private func moveCaret(extend: Bool, keepsGoalX: Bool = false, to destination: (TextPosition, Int) -> TextPosition?) {
        guard var current = selection ?? caretAtTopOfScreen() else { return }
        if current.selectsWholeLines {
            current = DiffSelection(column: current.column, anchor: TextPosition(row: current.start.row, column: 0),
                                    head: TextPosition(row: current.end.row, column: lineLength(atRow: current.end.row, column: current.column)))
        }
        if !keepsGoalX {
            caretGoalX = nil
        }
        guard let position = destination(current.head, current.column) else {
            NSSound.beep()
            return
        }
        current.head = position
        if !extend {
            current.anchor = position
        }
        selection = current
        hover = nil
        revealRow(position.row, margin: lineHeight * 2)
        let x = xOffset(of: position, column: current.column)
        revealTextRange(from: x, to: x + 2)
        placeGutterActions()
        setNeedsDisplay(visibleRect)
        NSAccessibility.post(element: self, notification: .selectedTextChanged)
    }

    private func caretAtTopOfScreen() -> DiffSelection? {
        let column = layout == .split ? 1 : 0
        guard let row = visibleRows.first(where: { line(atRow: $0, column: column) != nil }) else { return nil }
        return .caret(at: TextPosition(row: row, column: 0), column: column)
    }

    private func nextRowWithCode(after row: Int, column: Int, step: Int) -> Int? {
        var index = row + step
        while rows.indices.contains(index) {
            if line(atRow: index, column: column) != nil { return index }
            index += step
        }
        return nil
    }

    private func characterLeft(of position: TextPosition, column: Int) -> TextPosition? {
        if position.column > 0 {
            return TextPosition(row: position.row, column: position.column - 1)
        }
        guard let row = nextRowWithCode(after: position.row, column: column, step: -1) else { return nil }
        return TextPosition(row: row, column: lineLength(atRow: row, column: column))
    }

    private func characterRight(of position: TextPosition, column: Int) -> TextPosition? {
        if position.column < lineLength(atRow: position.row, column: column) {
            return TextPosition(row: position.row, column: position.column + 1)
        }
        guard let row = nextRowWithCode(after: position.row, column: column, step: 1) else { return nil }
        return TextPosition(row: row, column: 0)
    }

    private func wordLeft(of position: TextPosition, column: Int) -> TextPosition? {
        guard position.column > 0, let line = line(atRow: position.row, column: column) else {
            return characterLeft(of: position, column: column)
        }
        let characters = Array(line.text.utf16)
        var index = min(position.column, characters.count)
        while index > 0 && !isWordCharacter(characters[index - 1]) { index -= 1 }
        while index > 0 && isWordCharacter(characters[index - 1]) { index -= 1 }
        return TextPosition(row: position.row, column: index)
    }

    private func wordRight(of position: TextPosition, column: Int) -> TextPosition? {
        guard let line = line(atRow: position.row, column: column), position.column < line.text.utf16.count else {
            return characterRight(of: position, column: column)
        }
        let characters = Array(line.text.utf16)
        var index = position.column
        while index < characters.count && !isWordCharacter(characters[index]) { index += 1 }
        while index < characters.count && isWordCharacter(characters[index]) { index += 1 }
        return TextPosition(row: position.row, column: index)
    }

    private func lineUp(from position: TextPosition, column: Int) -> TextPosition? {
        verticalMove(from: position, column: column, toRow: nextRowWithCode(after: position.row, column: column, step: -1))
    }

    private func lineDown(from position: TextPosition, column: Int) -> TextPosition? {
        verticalMove(from: position, column: column, toRow: nextRowWithCode(after: position.row, column: column, step: 1))
    }

    private func pageMove(from position: TextPosition, column: Int, direction: CGFloat) -> TextPosition? {
        let distance = max(lineHeight, visibleRect.height - lineHeight * 2)
        let targetY = min(max(0, rowTops[position.row] + direction * distance), max(0, (rowTops.last ?? 1) - 1))
        guard let row = rowIndex(atY: targetY) else { return nil }
        let step = direction > 0 ? 1 : -1
        let target = line(atRow: row, column: column) != nil ? row : nextRowWithCode(after: row, column: column, step: step)
        return verticalMove(from: position, column: column, toRow: target)
    }

    /// Keeps the caret at the same x position as it moves between lines of different lengths.
    private func verticalMove(from position: TextPosition, column: Int, toRow row: Int?) -> TextPosition? {
        guard let row else { return nil }
        let goalX = caretGoalX ?? xOffset(of: position, column: column)
        caretGoalX = goalX
        return TextPosition(row: row, column: textColumn(atX: goalX, row: row, column: column))
    }

    private func lineStart(of position: TextPosition, column: Int) -> TextPosition? {
        TextPosition(row: position.row, column: 0)
    }

    private func lineEnd(of position: TextPosition, column: Int) -> TextPosition? {
        TextPosition(row: position.row, column: lineLength(atRow: position.row, column: column))
    }

    private func documentStart(_ position: TextPosition, column: Int) -> TextPosition? {
        rows.indices.first { line(atRow: $0, column: column) != nil }.map { TextPosition(row: $0, column: 0) }
    }

    private func documentEnd(_ position: TextPosition, column: Int) -> TextPosition? {
        rows.indices.last { line(atRow: $0, column: column) != nil }.map { TextPosition(row: $0, column: lineLength(atRow: $0, column: column)) }
    }

    // MARK: - Standard key binding commands

    override func moveLeft(_ sender: Any?) {
        if let current = selection, !current.isCaret {
            moveCaret(extend: false) { _, _ in current.start }
        } else {
            moveCaret(extend: false, to: characterLeft)
        }
    }

    override func moveRight(_ sender: Any?) {
        if let current = selection, !current.isCaret {
            moveCaret(extend: false) { _, _ in current.end }
        } else {
            moveCaret(extend: false, to: characterRight)
        }
    }

    override func moveUp(_ sender: Any?) { moveCaret(extend: false, keepsGoalX: true, to: lineUp) }
    override func moveDown(_ sender: Any?) { moveCaret(extend: false, keepsGoalX: true, to: lineDown) }
    override func moveLeftAndModifySelection(_ sender: Any?) { moveCaret(extend: true, to: characterLeft) }
    override func moveRightAndModifySelection(_ sender: Any?) { moveCaret(extend: true, to: characterRight) }
    override func moveUpAndModifySelection(_ sender: Any?) { moveCaret(extend: true, keepsGoalX: true, to: lineUp) }
    override func moveDownAndModifySelection(_ sender: Any?) { moveCaret(extend: true, keepsGoalX: true, to: lineDown) }

    override func moveWordLeft(_ sender: Any?) { moveCaret(extend: false, to: wordLeft) }
    override func moveWordRight(_ sender: Any?) { moveCaret(extend: false, to: wordRight) }
    override func moveWordLeftAndModifySelection(_ sender: Any?) { moveCaret(extend: true, to: wordLeft) }
    override func moveWordRightAndModifySelection(_ sender: Any?) { moveCaret(extend: true, to: wordRight) }

    override func moveToLeftEndOfLine(_ sender: Any?) { moveCaret(extend: false, to: lineStart) }
    override func moveToRightEndOfLine(_ sender: Any?) { moveCaret(extend: false, to: lineEnd) }
    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) { moveCaret(extend: true, to: lineStart) }
    override func moveToRightEndOfLineAndModifySelection(_ sender: Any?) { moveCaret(extend: true, to: lineEnd) }
    override func moveToBeginningOfLine(_ sender: Any?) { moveCaret(extend: false, to: lineStart) }
    override func moveToEndOfLine(_ sender: Any?) { moveCaret(extend: false, to: lineEnd) }
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) { moveCaret(extend: true, to: lineStart) }
    override func moveToEndOfLineAndModifySelection(_ sender: Any?) { moveCaret(extend: true, to: lineEnd) }

    override func moveToBeginningOfDocument(_ sender: Any?) { moveCaret(extend: false, to: documentStart) }
    override func moveToEndOfDocument(_ sender: Any?) { moveCaret(extend: false, to: documentEnd) }
    override func moveToBeginningOfDocumentAndModifySelection(_ sender: Any?) { moveCaret(extend: true, to: documentStart) }
    override func moveToEndOfDocumentAndModifySelection(_ sender: Any?) { moveCaret(extend: true, to: documentEnd) }
    override func scrollToBeginningOfDocument(_ sender: Any?) { moveToBeginningOfDocument(sender) }
    override func scrollToEndOfDocument(_ sender: Any?) { moveToEndOfDocument(sender) }

    override func pageUp(_ sender: Any?) { moveCaret(extend: false, keepsGoalX: true) { self.pageMove(from: $0, column: $1, direction: -1) } }
    override func pageDown(_ sender: Any?) { moveCaret(extend: false, keepsGoalX: true) { self.pageMove(from: $0, column: $1, direction: 1) } }
    override func pageUpAndModifySelection(_ sender: Any?) { moveCaret(extend: true, keepsGoalX: true) { self.pageMove(from: $0, column: $1, direction: -1) } }
    override func pageDownAndModifySelection(_ sender: Any?) { moveCaret(extend: true, keepsGoalX: true) { self.pageMove(from: $0, column: $1, direction: 1) } }
    override func scrollPageUp(_ sender: Any?) { pageUp(sender) }
    override func scrollPageDown(_ sender: Any?) { pageDown(sender) }
}

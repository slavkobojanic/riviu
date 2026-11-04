import AppKit
import RiviuDiff
import RiviuSyntax

private let foregroundColorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

extension DiffCanvasView {
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(palette.background)
        context.fill(dirtyRect)

        if var row = rowIndex(atY: dirtyRect.minY) {
            while row < rows.count && rowTops[row] < dirtyRect.maxY {
                drawRow(row, in: context)
                row += 1
            }
        }

        if layout == .split {
            context.setFillColor(palette.separator)
            context.fill(CGRect(x: halfWidth, y: dirtyRect.minY, width: 1, height: dirtyRect.height))
        }
    }

    private func drawRow(_ row: Int, in context: CGContext) {
        let rect = rowRect(row)
        switch rows[row] {
        case let .split(base, head):
            drawLine(base, row: row, column: 0, in: rect, context: context)
            drawLine(head, row: row, column: 1, in: rect, context: context)

        case let .unified(line, baseIndex, headIndex):
            drawLine(line, row: row, column: 0, in: rect, context: context, baseNumber: baseIndex.map { $0 + 1 },
                     headNumber: headIndex.map { $0 + 1 })

        case let .collapsed(_, hiddenLineCount, change):
            context.setFillColor(palette.collapsedRow)
            context.fill(rect)
            let textY = rect.minY + (rect.height - lineHeight) / 2
            let text = change.map { "⋯   \(hiddenLineCount) \(hiddenLineCount == 1 ? "line" : "lines") · \($0.title), hidden" }
                ?? "⋯   \(hiddenLineCount) unchanged lines"
            draw(label(text), x: gutterWidth + 10, y: textY, in: context)

        case let .attachment(_, side):
            drawAttachmentBackground(side: side, in: rect, context: context)
        }
    }

    /// Attachments sit in their side's column; the other column shows filler.
    private func drawAttachmentBackground(side: DiffSide, in rect: CGRect, context: CGContext) {
        let column = layout == .split ? side.rawValue : 0
        if layout == .split {
            let other = 1 - column
            context.setFillColor(palette.filler)
            context.fill(CGRect(x: columnX(other), y: rect.minY, width: columnWidth(other), height: rect.height))
        }
        context.setFillColor(palette.gutter)
        context.fill(CGRect(x: columnX(column), y: rect.minY, width: gutterWidth, height: rect.height))
    }

    // MARK: - Lines

    private func drawLine(_ line: DiffLine?, row: Int, column: Int, in rowRect: CGRect, context: CGContext,
                          baseNumber: Int? = nil, headNumber: Int? = nil) {
        let cell = CGRect(x: columnX(column), y: rowRect.minY, width: columnWidth(column), height: rowRect.height)
        guard let line else {
            context.setFillColor(palette.filler)
            context.fill(cell)
            return
        }
        let gutter = CGRect(x: cell.minX, y: cell.minY, width: gutterWidth, height: cell.height)
        let codeArea = CGRect(x: gutter.maxX, y: cell.minY, width: cell.width - gutterWidth, height: cell.height)
        // Moved, renamed and reformatted lines are faded so the eye skips to real changes.
        context.saveGState()
        defer { context.restoreGState() }
        if line.cosmeticChange != nil {
            context.setAlpha(0.5)
        }

        drawChangeBackground(for: line.kind, cell: cell, gutter: gutter, context: context)
        let isEmphasized = drawEmphasis(row: row, column: column, gutter: gutter, codeArea: codeArea, context: context)
        drawLineNumbers(for: line, gutter: gutter, emphasized: isEmphasized, baseNumber: baseNumber, headNumber: headNumber, context: context)

        let textLine = cachedTextLine(for: line, row: row, column: column)
        let textX = textOriginX(column)
        context.saveGState()
        context.clip(to: codeArea)
        drawWordChange(line, textLine: textLine, textX: textX, codeArea: codeArea, context: context)
        drawFindMatches(in: line, row: row, column: column, textLine: textLine, textX: textX, codeArea: codeArea, context: context)
        drawSelection(row: row, column: column, line: line, textLine: textLine, textX: textX, codeArea: codeArea, context: context)
        draw(textLine, x: textX, y: cell.minY, in: context)
        drawCaret(row: row, column: column, line: line, textLine: textLine, textX: textX, codeArea: codeArea, context: context)
        context.restoreGState()
        if let change = line.cosmeticChange, line.startsChange {
            drawChangeLabel(change.title, codeArea: codeArea, context: context)
        }
    }

    /// "Formatting only", right-aligned on the first line of a cosmetic hunk.
    private func drawChangeLabel(_ title: String, codeArea: CGRect, context: CGContext) {
        let textLine = label(title)
        let width = CGFloat(CTLineGetTypographicBounds(textLine, nil, nil, nil))
        let capsule = CGRect(x: codeArea.maxX - width - 22, y: codeArea.minY + 2, width: width + 14, height: codeArea.height - 4)
        context.setFillColor(palette.collapsedRow)
        context.addPath(CGPath(roundedRect: capsule, cornerWidth: capsule.height / 2, cornerHeight: capsule.height / 2, transform: nil))
        context.fillPath()
        draw(textLine, x: capsule.minX + 7, y: codeArea.minY, in: context)
    }

    private func drawChangeBackground(for kind: DiffLine.Kind, cell: CGRect, gutter: CGRect, context: CGContext) {
        switch kind {
        case .unchanged:
            context.setFillColor(palette.gutter)
            context.fill(gutter)
        case .added, .removed:
            let added = kind == .added
            context.setFillColor(added ? palette.addedLine : palette.removedLine)
            context.fill(cell)
            context.setFillColor(added ? palette.addedGutter : palette.removedGutter)
            context.fill(gutter)
            context.setFillColor(added ? palette.addedMarker : palette.removedMarker)
            context.fill(CGRect(x: gutter.maxX - 3, y: gutter.minY, width: 3, height: gutter.height))
        }
    }

    /// Tints the hovered block and multi-line selections. Returns whether this row is emphasized, in which case its
    /// line numbers are drawn in the full text color so they stay readable on the tint.
    private func drawEmphasis(row: Int, column: Int, gutter: CGRect, codeArea: CGRect, context: CGContext) -> Bool {
        var isEmphasized = false
        if let hover, hover.column == column, hover.block.contains(row) {
            context.setFillColor(palette.blockGutter)
            context.fill(gutter)
            context.setFillColor(palette.blockText)
            context.fill(codeArea)
            isEmphasized = true
        }
        if let selection, selection.column == column, !selection.isCaret,
           (selection.start.row...selection.end.row).contains(row),
           selection.selectsWholeLines || selection.start.row != selection.end.row {
            context.setFillColor(palette.selectionGutter)
            context.fill(gutter)
            isEmphasized = true
        }
        if isEmphasized {
            context.setFillColor(palette.accent)
            context.fill(CGRect(x: gutter.minX, y: gutter.minY, width: 3, height: gutter.height))
        }
        return isEmphasized
    }

    private func drawLineNumbers(for line: DiffLine, gutter: CGRect, emphasized: Bool, baseNumber: Int?, headNumber: Int?,
                                 context: CGContext) {
        let sign = line.kind == .added ? "+" : "−"
        if layout == .split {
            drawLineNumber(line.number, rightEdge: gutter.minX + lineNumberWidth, y: gutter.minY, emphasized: emphasized, context: context)
            if showsChangeSigns && line.kind != .unchanged {
                draw(label(sign), x: gutter.minX + lineNumberWidth + 1, y: gutter.minY, in: context)
            }
        } else {
            if let baseNumber {
                drawLineNumber(baseNumber, rightEdge: lineNumberWidth, y: gutter.minY, emphasized: emphasized, context: context)
            }
            if let headNumber {
                drawLineNumber(headNumber, rightEdge: lineNumberWidth * 2, y: gutter.minY, emphasized: emphasized, context: context)
            }
            if line.kind != .unchanged {
                draw(label(sign), x: lineNumberWidth * 2 + 5, y: gutter.minY, in: context)
            }
        }
    }

    private func drawWordChange(_ line: DiffLine, textLine: CTLine, textX: CGFloat, codeArea: CGRect, context: CGContext) {
        guard let range = line.changedRange, !range.isEmpty else { return }
        let start = CTLineGetOffsetForStringIndex(textLine, range.lowerBound, nil)
        let end = CTLineGetOffsetForStringIndex(textLine, range.upperBound, nil)
        context.setFillColor(line.kind == .added ? palette.addedWord : palette.removedWord)
        context.fill(CGRect(x: textX + start, y: codeArea.minY + 2, width: max(3, end - start), height: codeArea.height - 4))
    }

    private func drawSelection(row: Int, column: Int, line: DiffLine, textLine: CTLine, textX: CGFloat, codeArea: CGRect,
                               context: CGContext) {
        guard let selection, selection.column == column, !selection.isCaret,
              row >= selection.start.row, row <= selection.end.row else { return }
        var left = codeArea.minX
        var right = codeArea.maxX
        if !selection.selectsWholeLines {
            let length = line.text.utf16.count
            if row == selection.start.row {
                left = textX + CTLineGetOffsetForStringIndex(textLine, min(selection.start.column, length), nil)
            } else {
                left = textX - 2
            }
            if row == selection.end.row {
                right = textX + CTLineGetOffsetForStringIndex(textLine, min(selection.end.column, length), nil)
            }
        }
        guard right > left else { return }
        context.setFillColor(palette.selection)
        context.fill(CGRect(x: left, y: codeArea.minY, width: right - left, height: codeArea.height))
    }

    private func drawCaret(row: Int, column: Int, line: DiffLine, textLine: CTLine, textX: CGFloat, codeArea: CGRect,
                           context: CGContext) {
        guard let selection, selection.isCaret, selection.column == column, selection.head.row == row,
              window?.firstResponder === self else { return }
        let offset = CTLineGetOffsetForStringIndex(textLine, min(selection.head.column, line.text.utf16.count), nil)
        context.setFillColor(palette.accent)
        context.fill(CGRect(x: textX + offset - 0.5, y: codeArea.minY + 3, width: 2, height: codeArea.height - 6))
    }

    // MARK: - Text

    func draw(_ textLine: CTLine, x: CGFloat, y: CGFloat, in context: CGContext) {
        // The view is flipped (y grows downward), so the text matrix flips glyphs back upright.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: y + baselineOffset)
        CTLineDraw(textLine, context)
    }

    private func drawLineNumber(_ number: Int, rightEdge: CGFloat, y: CGFloat, emphasized: Bool, context: CGContext) {
        let key = number * 2 + (emphasized ? 1 : 0)
        let textLine: CTLine
        if let cached = lineNumberCache[key] {
            textLine = cached
        } else {
            let color = emphasized ? palette.lineNumberEmphasized : palette.lineNumber
            textLine = CTLineCreateWithAttributedString(NSAttributedString(string: String(number), attributes: [
                .font: font, foregroundColorKey: color,
            ]))
            lineNumberCache[key] = textLine
        }
        let width = CGFloat(CTLineGetTypographicBounds(textLine, nil, nil, nil))
        draw(textLine, x: rightEdge - width - 6, y: y, in: context)
    }

    func label(_ text: String) -> CTLine {
        if let cached = labelCache[text] { return cached }
        let textLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, foregroundColorKey: palette.lineNumber,
        ]))
        labelCache[text] = textLine
        return textLine
    }

    /// The syntax-highlighted text of a line, built once and reused while it stays on screen.
    func cachedTextLine(for line: DiffLine, row: Int, column: Int) -> CTLine {
        let key = row * 2 + column
        if let cached = textLineCache[key] { return cached }
        if textLineCache.count > 6000 {
            textLineCache.removeAll(keepingCapacity: true)
        }

        let text = NSMutableAttributedString(string: line.text, attributes: [.font: font, foregroundColorKey: palette.text])
        let length = text.length
        for token in syntax(for: line.side)?.tokens(line: line.index) ?? [] {
            guard let color = syntaxColor(for: token.name), token.range.lowerBound < length else { continue }
            let end = min(token.range.upperBound, length)
            text.addAttribute(foregroundColorKey, value: color, range: NSRange(location: token.range.lowerBound, length: end - token.range.lowerBound))
        }
        let textLine = CTLineCreateWithAttributedString(text)
        textLineCache[key] = textLine
        return textLine
    }

    private func syntaxColor(for captureName: String) -> CGColor? {
        if let cached = syntaxColorCache[captureName] { return cached }
        let color = theme.color(for: captureName)?.cgColor
        syntaxColorCache[captureName] = color
        return color
    }
}

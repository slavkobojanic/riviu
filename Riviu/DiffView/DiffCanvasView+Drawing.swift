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
            // Clicking the row shows the hidden lines, so it highlights under the mouse like a button.
            context.setFillColor(row == hoveredCollapsedRow ? palette.collapsedRowHovered : palette.collapsedRow)
            context.fill(rect)
            let textY = rect.minY + (rect.height - lineHeight) / 2
            drawExpandGlyph(in: CGRect(x: 0, y: rect.minY, width: gutterWidth, height: rect.height))
            let text = change.map { "\($0.title), \(hiddenLineCount) \(hiddenLineCount == 1 ? "line" : "lines") hidden" }
                ?? "\(hiddenLineCount) unchanged lines"
            draw(label(text, color: palette.collapsedLabel), x: gutterWidth + 10, y: textY, in: context)

        case let .attachment(_, side):
            drawAttachmentBackground(side: side, in: rect, context: context)
        }
    }

    /// The up-and-down arrows in a collapsed row's gutter, which say the row expands.
    private func drawExpandGlyph(in gutter: CGRect) {
        let image = expandGlyphImage()
        let size = image.size
        let glyphRect = CGRect(x: gutter.midX - size.width / 2, y: gutter.midY - size.height / 2,
                               width: size.width, height: size.height)
        image.draw(in: glyphRect.integral, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func expandGlyphImage() -> NSImage {
        if let expandGlyph { return expandGlyph }
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(cgColor: palette.collapsedLabel) ?? .secondaryLabelColor]))
        let image = NSImage(systemSymbolName: "arrow.up.and.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
        expandGlyph = image
        return image
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
        // Moved, renamed and reformatted lines get a fainter tint so the eye skips to real changes.
        // Only the tint fades; the code and line numbers stay fully readable.
        let isFaded = line.cosmeticChange != nil && palette.fadesCosmeticChanges

        drawChangeBackground(for: line.kind, cell: cell, gutter: gutter, faded: isFaded, context: context)
        let isEmphasized = drawEmphasis(row: row, column: column, gutter: gutter, codeArea: codeArea, context: context)
        drawLineNumbers(for: line, gutter: gutter, emphasized: isEmphasized, baseNumber: baseNumber, headNumber: headNumber, context: context)

        let textLine = cachedTextLine(for: line, row: row, column: column)
        let textX = textOriginX(column)
        context.saveGState()
        context.clip(to: codeArea)
        drawWordChange(line, textLine: textLine, textX: textX, codeArea: codeArea, faded: isFaded, context: context)
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
        let textLine = label(title, color: palette.collapsedLabel)
        let width = CGFloat(CTLineGetTypographicBounds(textLine, nil, nil, nil))
        let capsule = CGRect(x: codeArea.maxX - width - 22, y: codeArea.minY + 2, width: width + 14, height: codeArea.height - 4)
        context.setFillColor(palette.collapsedRow)
        context.addPath(CGPath(roundedRect: capsule, cornerWidth: capsule.height / 2, cornerHeight: capsule.height / 2, transform: nil))
        context.fillPath()
        draw(textLine, x: capsule.minX + 7, y: codeArea.minY, in: context)
    }

    private func drawChangeBackground(for kind: DiffLine.Kind, cell: CGRect, gutter: CGRect, faded: Bool, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        if faded {
            context.setAlpha(0.5)
        }
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
        let style = LineNumberStyle(kind: line.kind, emphasized: emphasized)
        let sign = label(line.kind == .added ? "+" : "−", color: style.color(in: palette))
        if layout == .split {
            drawLineNumber(line.number, rightEdge: gutter.minX + lineNumberWidth, y: gutter.minY, style: style, context: context)
            if showsChangeSigns && line.kind != .unchanged {
                draw(sign, x: gutter.minX + lineNumberWidth + 1, y: gutter.minY, in: context)
            }
        } else {
            if let baseNumber {
                drawLineNumber(baseNumber, rightEdge: lineNumberWidth, y: gutter.minY, style: style, context: context)
            }
            if let headNumber {
                drawLineNumber(headNumber, rightEdge: lineNumberWidth * 2, y: gutter.minY, style: style, context: context)
            }
            if line.kind != .unchanged {
                draw(sign, x: lineNumberWidth * 2 + 5, y: gutter.minY, in: context)
            }
        }
    }

    private func drawWordChange(_ line: DiffLine, textLine: CTLine, textX: CGFloat, codeArea: CGRect, faded: Bool,
                                context: CGContext) {
        guard let range = line.changedRange, !range.isEmpty else { return }
        let start = CTLineGetOffsetForStringIndex(textLine, range.lowerBound, nil)
        let end = CTLineGetOffsetForStringIndex(textLine, range.upperBound, nil)
        let color = line.kind == .added ? palette.addedWord : palette.removedWord
        context.setFillColor(faded ? color.copy(alpha: color.alpha * 0.5) ?? color : color)
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

    private func drawLineNumber(_ number: Int, rightEdge: CGFloat, y: CGFloat, style: LineNumberStyle, context: CGContext) {
        let key = number * 4 + style.rawValue
        let textLine: CTLine
        if let cached = lineNumberCache[key] {
            textLine = cached
        } else {
            textLine = CTLineCreateWithAttributedString(NSAttributedString(string: String(number), attributes: [
                .font: font, foregroundColorKey: style.color(in: palette),
            ]))
            lineNumberCache[key] = textLine
        }
        let width = CGFloat(CTLineGetTypographicBounds(textLine, nil, nil, nil))
        draw(textLine, x: rightEdge - width - 6, y: y, in: context)
    }

    /// A short piece of gutter-style text. Drawn in the line-number color unless another is given.
    func label(_ text: String, color: CGColor? = nil) -> CTLine {
        let color = color ?? palette.lineNumber
        let key = LabelKey(text: text, color: color)
        if let cached = labelCache[key] { return cached }
        let textLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, foregroundColorKey: color,
        ]))
        labelCache[key] = textLine
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

/// Which color a line number is drawn in. The raw value is part of the line-number cache key.
private enum LineNumberStyle: Int {
    case plain = 0
    case emphasized = 1
    case added = 2
    case removed = 3

    init(kind: DiffLine.Kind, emphasized: Bool) {
        if emphasized {
            self = .emphasized
        } else {
            switch kind {
            case .unchanged: self = .plain
            case .added: self = .added
            case .removed: self = .removed
            }
        }
    }

    func color(in palette: DiffPalette) -> CGColor {
        switch self {
        case .plain: palette.lineNumber
        case .emphasized: palette.lineNumberEmphasized
        case .added: palette.addedLineNumber
        case .removed: palette.removedLineNumber
        }
    }
}

/// Labels are cached by their text and color, since the same text can be drawn in different colors.
struct LabelKey: Hashable {
    let text: String
    let color: CGColor
}

import AppKit
import RiviuDiff
import RiviuSyntax
import SwiftUI

/// A position in the text of one column: a row and a UTF-16 offset in that row's line.
struct TextPosition: Comparable {
    var row: Int
    var column: Int

    static func < (a: Self, b: Self) -> Bool {
        (a.row, a.column) < (b.row, b.column)
    }
}

/// A selection in one column of the diff. When `anchor == head` it is just a caret.
struct DiffSelection {
    /// 0 is the left (or only) column, 1 is the right column of the split view.
    var column: Int
    var anchor: TextPosition
    var head: TextPosition
    /// Whole-line selection, made by dragging over line numbers or triple-clicking.
    var selectsWholeLines = false

    var start: TextPosition { min(anchor, head) }
    var end: TextPosition { max(anchor, head) }
    var isCaret: Bool { !selectsWholeLines && anchor == head }

    static func caret(at position: TextPosition, column: Int) -> DiffSelection {
        DiffSelection(column: column, anchor: position, head: position)
    }
}

/// The gutter row under the mouse, and the block of rows it belongs to.
struct GutterHover {
    var row: Int
    var column: Int
    var block: ClosedRange<Int>
}

/// The code diff: a single view that draws only the rows on screen.
///
/// Both columns of the split view read from the same `rows`, so they always line up. Most rows are one
/// line of code; collapsed regions and attachments (comments, findings) have their own heights, so each
/// row's top edge is stored in `rowTops` and looked up with a binary search.
///
/// The behaviour is split across extensions: drawing, hover, selection, keyboard, find, scrolling and
/// accessibility each have their own file.
final class DiffCanvasView: NSView, NSPopoverDelegate {
    // MARK: Callbacks

    var onExpandSegment: ((Int) -> Void)?
    var onComment: ((CodeTarget) -> Void)?
    var onFindStatus: ((FindStatus) -> Void)?
    var makeAttachmentView: ((AttachmentID) -> NSView)?
    var makeExplainPopover: ((CodeTarget) -> NSViewController)?
    var makeHotPathPopover: ((CodeTarget) -> NSViewController)?
    /// For ⌘-click on a name: returns a popover to show, or nil after jumping straight to the definition.
    var goToDefinition: ((_ name: String, _ target: CodeTarget) -> NSViewController?)?

    // MARK: Content

    var rows: [DiffRow] = []
    /// `rowTops[i]` is the y of row i's top edge; the last element is the total height.
    var rowTops: [CGFloat] = [0]
    var layout: DiffLayout = .split
    var filePath = ""
    var baseSyntax: SyntaxDocument?
    var headSyntax: SyntaxDocument?

    // MARK: Appearance

    var themeFamily: EditorThemeFamily = .one
    var theme = EditorThemeFamily.one.theme(dark: false)
    var palette = DiffPalette(theme: EditorThemeFamily.one.theme(dark: false), increaseContrast: false)
    var showsChangeSigns = false
    var font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    var lineSpacing = LineSpacing.standard
    var lineHeight: CGFloat = 24
    var baselineOffset: CGFloat = 16
    var characterWidth: CGFloat = 8

    let lineNumberWidth: CGFloat = 46
    var gutterWidth: CGFloat { layout == .split ? lineNumberWidth + 14 : lineNumberWidth * 2 + 22 }
    var collapsedRowHeight: CGFloat { lineHeight + 8 }

    // MARK: Caches (cleared whenever content or appearance changes)

    var textLineCache: [Int: CTLine] = [:]
    var lineNumberCache: [Int: CTLine] = [:]
    var labelCache: [String: CTLine] = [:]
    var syntaxColorCache: [String: CGColor?] = [:]

    // MARK: Attachments

    var attachmentHeights: [AttachmentID: CGFloat] = [:]
    var attachmentViews: [AttachmentID: NSView] = [:]

    // MARK: Interaction state

    var hover: GutterHover?
    var selection: DiffSelection?
    /// Remembered x position while moving the caret up and down, so it doesn't drift on short lines.
    var caretGoalX: CGFloat?
    var isDraggingSelection = false
    let gutterActions = GutterActionsHostingView(rootView: GutterActions(onExplain: {}, onHotPath: {}, onComment: {}))
    /// The buttons alone, measured once.
    lazy var gutterActionsSize = gutterActions.fittingSize
    let popover = NSPopover()

    var horizontalOffset: CGFloat = 0
    var widestLineWidth: CGFloat = 0
    var scrollWheelMonitor: Any?

    var findQuery = ""
    var findMatches: [FindMatch] = []
    var currentMatchIndex = -1

    // MARK: - Setup

    override init(frame: NSRect) {
        super.init(frame: frame)
        gutterActions.rootView = GutterActions(onExplain: { [weak self] in self?.explainTarget() },
                                               onHotPath: { [weak self] in self?.showHotPath() },
                                               onComment: { [weak self] in self?.commentOnTarget() })
        gutterActions.isHidden = true
        addSubview(gutterActions)
        popover.behavior = .transient
        popover.delegate = self
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        updateTextMetrics()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityDisplayOptionsChanged),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("DiffCanvasView is created in code.")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        setNeedsDisplay(visibleRect) // shows the caret
        return true
    }

    override func resignFirstResponder() -> Bool {
        setNeedsDisplay(visibleRect) // hides the caret
        return true
    }

    // MARK: - Updating content and appearance

    func setContent(rows newRows: [DiffRow], layout newLayout: DiffLayout, filePath newPath: String) {
        let isSameFile = newPath == filePath
        let scrollAnchor = isSameFile ? topVisibleLine() : nil
        clearInteraction()
        filePath = newPath
        rows = newRows
        layout = newLayout
        textLineCache.removeAll()
        widestLineWidth = CGFloat(rows.map(\.widestTextLength).max() ?? 0) * characterWidth
        if !isSameFile { horizontalOffset = 0 }
        clampHorizontalOffset()
        relayout()
        if let scrollAnchor {
            scroll(toLine: scrollAnchor)
        } else if !isSameFile {
            scrollToTop()
        }
        updateFindMatches(revealCurrent: false)
    }

    func setSyntax(base: SyntaxDocument?, head: SyntaxDocument?) {
        guard base !== baseSyntax || head !== headSyntax else { return }
        baseSyntax = base
        headSyntax = head
        textLineCache.removeAll()
        needsDisplay = true
    }

    func setThemeFamily(_ family: EditorThemeFamily) {
        guard family != themeFamily else { return }
        themeFamily = family
        updateTheme()
    }

    func setFont(_ newFont: NSFont, lineSpacing newSpacing: LineSpacing) {
        guard newFont != font || newSpacing != lineSpacing else { return }
        font = newFont
        lineSpacing = newSpacing
        updateTextMetrics()
        clearCaches()
        relayout()
    }

    private func updateTextMetrics() {
        let ascent = font.ascender
        let descent = -font.descender
        lineHeight = ceil(ascent + descent + font.leading) + lineSpacing.extraHeight
        baselineOffset = ((lineHeight - (ascent + descent)) / 2 + ascent).rounded()
        let sample = CTLineCreateWithAttributedString(NSAttributedString(string: "M", attributes: [.font: font]))
        characterWidth = CGFloat(CTLineGetTypographicBounds(sample, nil, nil, nil))
    }

    func updateTheme() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let workspace = NSWorkspace.shared
        theme = themeFamily.theme(dark: isDark)
        palette = DiffPalette(theme: theme, increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
        showsChangeSigns = workspace.accessibilityDisplayShouldDifferentiateWithoutColor
        clearCaches()
        enclosingScrollView?.backgroundColor = theme.background
        needsDisplay = true
    }

    private func clearCaches() {
        textLineCache.removeAll()
        lineNumberCache.removeAll()
        labelCache.removeAll()
        syntaxColorCache.removeAll()
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        updateTheme()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTheme()
    }

    // MARK: - Layout

    func height(of row: DiffRow) -> CGFloat {
        switch row {
        case .collapsed: collapsedRowHeight
        case let .attachment(id, _): attachmentHeights[id] ?? 120
        case .split, .unified: lineHeight
        }
    }

    func relayout() {
        rowTops = [0]
        rowTops.reserveCapacity(rows.count + 1)
        var y: CGFloat = 0
        for row in rows {
            y += height(of: row)
            rowTops.append(y)
        }
        matchFrameToContent()
        layoutAttachments()
        placeGutterActions()
        needsDisplay = true
    }

    /// The view is as wide as the scroll view and as tall as all its rows.
    private func matchFrameToContent() {
        guard let clipView = superview as? NSClipView else { return }
        let size = NSSize(width: clipView.bounds.width, height: rowTops.last ?? 0)
        if frame.size != size {
            setFrameSize(size)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            hover = nil
            clampHorizontalOffset()
            layoutAttachments()
            placeGutterActions()
            needsDisplay = true
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        guard let clipView = superview as? NSClipView else { return }
        clipView.postsFrameChangedNotifications = true
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipViewResized),
                                               name: NSView.frameDidChangeNotification, object: clipView)
        NotificationCenter.default.addObserver(self, selector: #selector(clipViewScrolled),
                                               name: NSView.boundsDidChangeNotification, object: clipView)
        matchFrameToContent()
        updateTheme()
    }

    @objc private func clipViewResized() {
        matchFrameToContent()
    }

    @objc private func clipViewScrolled() {
        updateHoverForCurrentMouseLocation()
    }

    // MARK: - Attachments (SwiftUI views hosted between rows)

    func layoutAttachments() {
        var visibleIDs = Set<AttachmentID>()
        for (index, row) in rows.enumerated() {
            guard case let .attachment(id, side) = row else { continue }
            visibleIDs.insert(id)
            let view = attachmentViews[id] ?? addAttachmentView(for: id)
            view.frame = attachmentFrame(row: index, side: side)
        }
        for (id, view) in attachmentViews where !visibleIDs.contains(id) {
            view.removeFromSuperview()
            attachmentViews[id] = nil
        }
    }

    private func addAttachmentView(for id: AttachmentID) -> NSView {
        let view = makeAttachmentView?(id) ?? NSView()
        addSubview(view, positioned: .below, relativeTo: gutterActions)
        attachmentViews[id] = view
        return view
    }

    private func attachmentFrame(row: Int, side: DiffSide) -> CGRect {
        let y = rowTops[row]
        let height = rowTops[row + 1] - y
        if layout == .split {
            let column = side.rawValue
            let x = columnX(column) + gutterWidth + 10
            return CGRect(x: x, y: y, width: max(160, columnWidth(column) - gutterWidth - 26), height: height)
        }
        let x = gutterWidth + 10
        return CGRect(x: x, y: y, width: max(160, min(860, bounds.width - x - 20)), height: height)
    }

    /// Called by an attachment's SwiftUI view whenever its ideal height changes.
    func setAttachmentHeight(_ height: CGFloat, for id: AttachmentID) {
        let height = ceil(height)
        guard abs((attachmentHeights[id] ?? -1) - height) >= 1 else { return }
        attachmentHeights[id] = height
        relayout()
    }

    // MARK: - Geometry

    var halfWidth: CGFloat { (bounds.width / 2).rounded(.down) }

    /// The x where a column starts. The unified view has a single column.
    func columnX(_ column: Int) -> CGFloat {
        layout == .split && column == 1 ? halfWidth : 0
    }

    func columnWidth(_ column: Int) -> CGFloat {
        guard layout == .split else { return bounds.width }
        return column == 0 ? halfWidth : bounds.width - halfWidth
    }

    func column(atX x: CGFloat) -> Int {
        layout == .split && x >= halfWidth ? 1 : 0
    }

    /// Where a column's code starts, after horizontal scrolling.
    func textOriginX(_ column: Int) -> CGFloat {
        columnX(column) + gutterWidth + 10 - horizontalOffset
    }

    func isInGutter(_ point: CGPoint) -> Bool {
        let column = column(atX: point.x)
        return point.x - columnX(column) < gutterWidth
    }

    func rowIndex(atY y: CGFloat) -> Int? {
        guard !rows.isEmpty else { return nil }
        let y = max(0, y)
        guard y < rowTops[rows.count] else { return nil }
        var low = 0
        var high = rows.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if rowTops[middle] <= y {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    func rowRect(_ row: Int) -> CGRect {
        guard row >= 0, row + 1 < rowTops.count else { return .zero }
        return CGRect(x: 0, y: rowTops[row], width: bounds.width, height: rowTops[row + 1] - rowTops[row])
    }

    /// The rows currently on screen.
    var visibleRows: Range<Int> {
        guard let first = rowIndex(atY: visibleRect.minY) else { return 0..<0 }
        var last = first
        while last < rows.count && rowTops[last] < visibleRect.maxY {
            last += 1
        }
        return first..<last
    }

    /// The line of code shown in a row's column, if any.
    func line(atRow row: Int, column: Int) -> DiffLine? {
        guard rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case let .split(base, head): return column == 0 ? base : head
        case let .unified(line, _, _): return column == 0 ? line : nil
        case .collapsed, .attachment: return nil
        }
    }

    func syntax(for side: DiffSide) -> SyntaxDocument? {
        side == .base ? baseSyntax : headSyntax
    }

    func clearInteraction() {
        if popover.isShown {
            popover.close()
        }
        hover = nil
        selection = nil
        caretGoalX = nil
        gutterActions.isHidden = true
    }

    func closePopover() {
        popover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        updateHoverForCurrentMouseLocation()
    }
}

private extension DiffRow {
    /// Length of the longest line in the row, counting a tab as four characters.
    var widestTextLength: Int {
        func length(_ line: DiffLine?) -> Int {
            guard let text = line?.text else { return 0 }
            let tabs = text.utf16.filter { $0 == 9 }.count
            return text.utf16.count + tabs * 3
        }
        switch self {
        case let .split(base, head): return max(length(base), length(head))
        case let .unified(line, _, _): return length(line)
        case .collapsed, .attachment: return 0
        }
    }
}

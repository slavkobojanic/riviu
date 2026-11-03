import AppKit
import RiviuDiff

/// Vertical scrolling is handled by the enclosing scroll view. Horizontal scrolling only moves the code,
/// so the line numbers stay put; it's implemented here with an offset applied while drawing.
extension DiffCanvasView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollWheelMonitor {
            NSEvent.removeMonitor(scrollWheelMonitor)
            self.scrollWheelMonitor = nil
        }
        guard window != nil else { return }
        // A monitor rather than a `scrollWheel(with:)` override: overriding it would turn off
        // AppKit's smooth background scrolling for the vertical direction.
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleHorizontalScroll(event) ?? false }
            return handled ? nil : event
        }
    }

    private func handleHorizontalScroll(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard visibleRect.contains(point), abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
        // Mouse wheels report lines rather than points.
        let distance = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 10
        scrollHorizontally(by: distance)
        return true
    }

    private var codeAreaWidth: CGFloat {
        columnWidth(0) - gutterWidth - 10
    }

    private var maximumHorizontalOffset: CGFloat {
        max(0, widestLineWidth + 40 - codeAreaWidth)
    }

    func clampHorizontalOffset() {
        horizontalOffset = min(max(0, horizontalOffset), maximumHorizontalOffset)
    }

    func scrollHorizontally(by distance: CGFloat) {
        let previous = horizontalOffset
        horizontalOffset -= distance
        clampHorizontalOffset()
        if horizontalOffset != previous {
            setNeedsDisplay(visibleRect)
        }
    }

    /// Scrolls sideways so text between two x offsets (measured from the start of the text) is visible.
    func revealTextRange(from start: CGFloat, to end: CGFloat) {
        if end - horizontalOffset > codeAreaWidth - 20 {
            horizontalOffset = end - codeAreaWidth + 60
        }
        if start < horizontalOffset + 10 {
            horizontalOffset = max(0, start - 60)
        }
        clampHorizontalOffset()
    }

    func revealRow(_ row: Int, margin: CGFloat) {
        guard row + 1 < rowTops.count, let scrollView = enclosingScrollView else { return }
        let visible = visibleRect
        let topInset = scrollView.contentView.contentInsets.top
        let top = rowTops[row]
        let bottom = rowTops[row + 1]
        guard top < visible.minY + topInset + margin || bottom > visible.maxY - margin else { return }
        let highest = -topInset
        let lowest = max(highest, bounds.height - visible.height)
        let target = top - (visible.height - topInset) * 0.35 - topInset
        scrollTo(y: min(max(highest, target), lowest))
    }

    /// Scrolls to a line if it's off screen. Returns false if no row shows that line.
    func revealLine(_ lineIndex: Int, on side: DiffSide) -> Bool {
        let match = rows.firstIndex { row in
            guard let indices = row.lineIndices else { return false }
            return (side == .head ? indices.head : indices.base) == lineIndex
        }
        guard let match else { return false }
        revealRow(match, margin: 40)
        return true
    }

    func scrollToTop() {
        guard let scrollView = enclosingScrollView else { return }
        scrollTo(y: -scrollView.contentView.contentInsets.top)
    }

    private func scrollTo(y: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Keeping your place

    /// The first line on screen and how far below the top edge it is, so it can be found again after the
    /// rows change (switching layout, expanding a section).
    struct ScrollAnchor {
        let baseIndex: Int?
        let headIndex: Int?
        let offsetFromTop: CGFloat
    }

    func topVisibleLine() -> ScrollAnchor? {
        for row in visibleRows {
            if let indices = rows[row].lineIndices {
                return ScrollAnchor(baseIndex: indices.base, headIndex: indices.head, offsetFromTop: rowTops[row] - visibleRect.minY)
            }
        }
        return nil
    }

    func scroll(toLine anchor: ScrollAnchor) {
        let match = rows.firstIndex { row in
            guard let indices = row.lineIndices else { return false }
            if let head = anchor.headIndex { return indices.head == head }
            return indices.base == anchor.baseIndex
        }
        guard let match else { return }
        scrollTo(y: rowTops[match] - anchor.offsetFromTop)
    }
}

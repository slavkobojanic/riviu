import AppKit
import RiviuDiff

/// Exposes the visible rows to VoiceOver as a list of lines.
extension DiffCanvasView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityRoleDescription() -> String? { "diff" }
    override func accessibilitySelectedText() -> String? { selectedText() }

    override func accessibilityLabel() -> String? {
        let name = (filePath as NSString).lastPathComponent
        return "Diff of \(name), \(layout == .split ? "split" : "unified") view"
    }

    override func accessibilityChildren() -> [Any]? {
        var children: [Any] = visibleRows.compactMap(accessibilityElement(forRow:))
        children += attachmentViews.values.filter { $0.frame.intersects(visibleRect) }
        if !gutterActions.isHidden {
            children.append(gutterActions)
        }
        return children
    }

    private func accessibilityElement(forRow row: Int) -> NSAccessibilityElement? {
        let element = AccessibleDiffRow()
        switch rows[row] {
        case let .split(base, head):
            let parts = base?.kind == .unchanged
                ? [spokenDescription(of: head, prefix: "")]
                : [spokenDescription(of: base, prefix: "Base "), spokenDescription(of: head, prefix: "Head ")]
            element.setAccessibilityLabel(parts.compactMap { $0 }.joined(separator: ". "))
            element.setAccessibilityRole(.staticText)
        case let .unified(line, _, _):
            element.setAccessibilityLabel(spokenDescription(of: line, prefix: line.side == .base ? "Base " : ""))
            element.setAccessibilityRole(.staticText)
        case let .collapsed(segmentIndex, hiddenLineCount):
            element.setAccessibilityLabel("\(hiddenLineCount) unchanged lines, collapsed")
            element.setAccessibilityRole(.button)
            element.onPress = { [weak self] in self?.onExpandSegment?(segmentIndex) }
        case .attachment:
            return nil
        }
        element.setAccessibilityParent(self)
        element.setAccessibilityFrameInParentSpace(rowRect(row))
        return element
    }

    private func spokenDescription(of line: DiffLine?, prefix: String) -> String? {
        guard let line else { return nil }
        let change = switch line.kind {
        case .added: ", added"
        case .removed: ", removed"
        case .unchanged: ""
        }
        let text = line.text.trimmingCharacters(in: .whitespaces)
        return "\(prefix)line \(line.number)\(change): \(text.isEmpty ? "blank" : text)"
    }
}

/// One row as an accessibility element; collapsed rows can be pressed to expand them.
/// AppKit calls accessibility methods on the main thread.
private nonisolated final class AccessibleDiffRow: NSAccessibilityElement, @unchecked Sendable {
    var onPress: (@MainActor () -> Void)?

    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        MainActor.assumeIsolated { onPress() }
        return true
    }
}

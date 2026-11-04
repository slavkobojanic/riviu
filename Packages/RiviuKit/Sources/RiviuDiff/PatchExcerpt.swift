/// A few lines of a unified diff, cut out by line numbers, for showing a small piece of a change.
public enum PatchExcerpt {
    public struct Line: Sendable, Hashable, Codable {
        public enum Kind: String, Sendable, Hashable, Codable {
            case context
            case added
            case removed
        }

        public let kind: Kind
        /// 1-based, or nil on the side the line isn't on.
        public let oldNumber: Int?
        public let newNumber: Int?
        public let text: String
    }

    /// The patch's lines whose numbers on `side` fall in `range` (1-based), with the removed or added lines
    /// in between. Lines the patch doesn't show, outside its hunks, aren't included.
    public static func lines(in patch: String, side: DiffSide, range: ClosedRange<Int>) -> [Line] {
        var result: [Line] = []
        var oldLine = 0
        var newLine = 0
        for rawLine in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = rawLine.wholeMatch(of: #/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@.*/#),
               let oldStart = Int(match.1), let newStart = Int(match.2) {
                oldLine = oldStart
                newLine = newStart
                continue
            }
            let text = String(rawLine.dropFirst())
            let line: Line
            switch rawLine.first {
            case "+":
                line = Line(kind: .added, oldNumber: nil, newNumber: newLine, text: text)
            case "-":
                line = Line(kind: .removed, oldNumber: oldLine, newNumber: nil, text: text)
            case " ":
                line = Line(kind: .context, oldNumber: oldLine, newNumber: newLine, text: text)
            default:
                continue // "\ No newline at end of file"
            }
            // A line that's only on the other side belongs with its neighbor: diffs list removed lines
            // before the added lines replacing them, so a removal goes with the next new line, and an
            // addition with the previous old line.
            let position = switch side {
            case .head: newLine
            case .base: line.kind == .added ? oldLine - 1 : oldLine
            }
            if range.contains(position) {
                result.append(line)
            }
            if line.kind != .added { oldLine += 1 }
            if line.kind != .removed { newLine += 1 }
        }
        return result
    }
}

/// Renders a file diff as standard unified-diff text ("@@ -10,3 +10,4 @@" hunks), for giving an AI model context
/// about a change, and as the patch of the built-in demo files.
public enum UnifiedDiffText {
    private struct Line {
        /// "+", "-" or " ".
        let prefix: Character
        let text: String
        /// 0-based, or nil on the side the line isn't on.
        let old: Int?
        let new: Int?
    }

    public static func make(for file: FileDiff, contextLines: Int = 3) -> String {
        let lines = allLines(of: file)
        var output = ["--- a/\(file.path)", "+++ b/\(file.path)"]
        for hunk in hunkRanges(in: lines, contextLines: contextLines) {
            output.append(header(for: lines, in: hunk))
            output += lines[hunk].map { "\($0.prefix)\($0.text)" }
        }
        return output.joined(separator: "\n")
    }

    private static func allLines(of file: FileDiff) -> [Line] {
        var lines: [Line] = []
        for segment in file.segments {
            switch segment {
            case let .unchanged(base, head):
                lines += zip(base, head).map { Line(prefix: " ", text: file.headLines[$1], old: $0, new: $1) }
            case let .changed(removed, added):
                lines += removed.map { Line(prefix: "-", text: file.baseLines[$0], old: $0, new: nil) }
                lines += added.map { Line(prefix: "+", text: file.headLines[$0], old: nil, new: $0) }
            }
        }
        return lines
    }

    /// Each change with its context lines; changes whose context touches are merged into one hunk.
    private static func hunkRanges(in lines: [Line], contextLines: Int) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for (position, line) in lines.enumerated() where line.prefix != " " {
            let range = max(0, position - contextLines)..<min(lines.count, position + contextLines + 1)
            if let last = ranges.last, range.lowerBound <= last.upperBound {
                ranges[ranges.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                ranges.append(range)
            }
        }
        return ranges
    }

    private static func header(for lines: [Line], in hunk: Range<Int>) -> String {
        let oldCount = lines[hunk].filter { $0.prefix != "+" }.count
        let newCount = lines[hunk].filter { $0.prefix != "-" }.count
        // A side with no lines in the hunk is numbered from the line before it, as git does.
        let oldStart = lines[hunk].lazy.compactMap(\.old).first.map { $0 + 1 } ?? lines[..<hunk.lowerBound].filter { $0.old != nil }.count
        let newStart = lines[hunk].lazy.compactMap(\.new).first.map { $0 + 1 } ?? lines[..<hunk.lowerBound].filter { $0.new != nil }.count
        return "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
    }
}

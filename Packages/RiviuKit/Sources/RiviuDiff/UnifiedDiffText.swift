/// Renders a file diff as compact unified-diff text, for giving an AI model context about a change.
public enum UnifiedDiffText {
    public static func make(for file: FileDiff, contextLines: Int = 3) -> String {
        var output = ["--- a/\(file.path)", "+++ b/\(file.path)"]
        let lastSegment = file.segments.count - 1

        for (index, segment) in file.segments.enumerated() {
            switch segment {
            case let .changed(removed, added):
                output += removed.map { "-" + file.baseLines[$0] }
                output += added.map { "+" + file.headLines[$0] }

            case let .unchanged(base, head):
                let lines = base.map { file.baseLines[$0] }
                let leading = index == 0 ? 0 : contextLines
                let trailing = index == lastSegment ? 0 : contextLines
                if lines.count <= leading + trailing {
                    output += lines.map { " " + $0 }
                    continue
                }
                output += lines.prefix(leading).map { " " + $0 }
                if trailing > 0 {
                    let firstShown = lines.count - trailing
                    output.append("@@ base line \(base.lowerBound + firstShown + 1), head line \(head.lowerBound + firstShown + 1) @@")
                    output += lines.suffix(trailing).map { " " + $0 }
                }
            }
        }
        return output.joined(separator: "\n")
    }
}

/// Adds line numbers to a unified diff, so an AI can point at exact lines.
///
///     @@ -10,3 +10,4 @@
///       10 | unchanged line
///     - 11 | removed line      (numbered in the old file)
///     + 11 | added line        (numbered in the new file)
public enum NumberedPatch {
    public static func make(from patch: String) -> String {
        var oldLine = 0
        var newLine = 0
        var output: [String] = []

        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if let (oldStart, newStart) = hunkStarts(in: line) {
                oldLine = oldStart
                newLine = newStart
                output.append(String(line))
                continue
            }
            let text = line.dropFirst()
            switch line.first {
            case "+":
                output.append("+ \(newLine) | \(text)")
                newLine += 1
            case "-":
                output.append("- \(oldLine) | \(text)")
                oldLine += 1
            case " ":
                output.append("  \(newLine) | \(text)")
                oldLine += 1
                newLine += 1
            default:
                // "\ No newline at end of file", or an empty trailing line.
                if !line.isEmpty { output.append(String(line)) }
            }
        }
        return output.joined(separator: "\n")
    }

    /// The new-file lines (1-based) each hunk covers. GitHub only accepts comments on these lines.
    public static func newLineRanges(in patch: String) -> [ClosedRange<Int>] {
        patch.split(separator: "\n").compactMap { line in
            guard let match = line.wholeMatch(of: #/@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@.*/#),
                  let start = Int(match.1) else { return nil }
            let count = match.2.flatMap { Int($0) } ?? 1
            return count > 0 ? start...(start + count - 1) : nil
        }
    }

    /// The first old and new line numbers from a hunk header like "@@ -10,3 +12,4 @@".
    private static func hunkStarts(in line: Substring) -> (old: Int, new: Int)? {
        guard let match = line.wholeMatch(of: #/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@.*/#),
              let old = Int(match.1), let new = Int(match.2) else { return nil }
        return (old, new)
    }
}

/// One "@@" hunk of a unified diff, with where its first change is.
public struct PatchHunk: Sendable, Equatable {
    /// 1-based first lines of the hunk, from its header.
    public let oldStart: Int
    public let newStart: Int
    /// 1-based line of the first added line, or nil if the hunk only removes.
    public let firstAddedLine: Int?
    /// 1-based line of the first removed line, or nil if the hunk only adds.
    public let firstRemovedLine: Int?
    /// The changed lines, without their "+" or "-", for describing the hunk.
    public let changedLines: [String]
    /// 1-based new-file numbers of every added line.
    public let addedLines: [Int]

    /// Splits a file's patch into its hunks.
    public static func hunks(in patch: String) -> [PatchHunk] {
        var hunks: [PatchHunk] = []
        var current: (oldStart: Int, newStart: Int, firstAdded: Int?, firstRemoved: Int?, changed: [String], added: [Int])?
        var oldLine = 0
        var newLine = 0

        func finish() {
            if let hunk = current {
                hunks.append(PatchHunk(oldStart: hunk.oldStart, newStart: hunk.newStart, firstAddedLine: hunk.firstAdded,
                                       firstRemovedLine: hunk.firstRemoved, changedLines: hunk.changed, addedLines: hunk.added))
            }
        }

        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = line.wholeMatch(of: #/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@.*/#),
               let old = Int(match.1), let new = Int(match.2) {
                finish()
                current = (old, new, nil, nil, [], [])
                oldLine = old
                newLine = new
                continue
            }
            guard current != nil else { continue }
            switch line.first {
            case "+":
                if current?.firstAdded == nil { current?.firstAdded = newLine }
                current?.added.append(newLine)
                current?.changed.append(String(line.dropFirst()))
                newLine += 1
            case "-":
                if current?.firstRemoved == nil { current?.firstRemoved = oldLine }
                current?.changed.append(String(line.dropFirst()))
                oldLine += 1
            case " ":
                oldLine += 1
                newLine += 1
            default:
                break
            }
        }
        finish()
        return hunks
    }
}

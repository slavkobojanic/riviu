/// Computes which lines were removed and added between two versions of a file.
public enum LineDiff {
    /// Runs Swift's built-in Myers diff and groups the result into unchanged and changed runs.
    public static func segments(base: [String], head: [String]) -> [DiffSegment] {
        var removedLines = Set<Int>()
        var insertedLines = Set<Int>()
        for change in head.difference(from: base) {
            switch change {
            case let .remove(offset, _, _): removedLines.insert(offset)
            case let .insert(offset, _, _): insertedLines.insert(offset)
            }
        }

        var segments: [DiffSegment] = []
        var b = 0
        var h = 0

        while b < base.count || h < head.count {
            let unchangedStart = (base: b, head: h)
            while b < base.count, h < head.count, !removedLines.contains(b), !insertedLines.contains(h) {
                b += 1
                h += 1
            }
            if b > unchangedStart.base {
                segments.append(.unchanged(base: unchangedStart.base..<b, head: unchangedStart.head..<h))
            }

            let changeStart = (base: b, head: h)
            while b < base.count, removedLines.contains(b) { b += 1 }
            while h < head.count, insertedLines.contains(h) { h += 1 }
            if b > changeStart.base || h > changeStart.head {
                appendChange(removed: changeStart.base..<b, added: changeStart.head..<h, to: &segments)
            }

            let madeProgress = b > unchangedStart.base || h > unchangedStart.head
            if !madeProgress {
                // Not reachable for a valid diff; treat whatever is left as changed so the loop always ends.
                appendChange(removed: b..<base.count, added: h..<head.count, to: &segments)
                break
            }
        }
        return segments
    }

    /// Adds a changed run, merging it with the previous one if they touch.
    private static func appendChange(removed: Range<Int>, added: Range<Int>, to segments: inout [DiffSegment]) {
        if case let .changed(previousRemoved, previousAdded)? = segments.last {
            segments[segments.count - 1] = .changed(removed: previousRemoved.lowerBound..<removed.upperBound,
                                                    added: previousAdded.lowerBound..<added.upperBound)
        } else {
            segments.append(.changed(removed: removed, added: added))
        }
    }
}

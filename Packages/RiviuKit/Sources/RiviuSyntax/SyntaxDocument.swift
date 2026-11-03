import Foundation
import SwiftTreeSitter

/// A highlight capture clipped to one line. `range` is in UTF-16 units relative to the line start.
public struct SyntaxToken: Sendable, Hashable {
    public let range: Range<Int>
    public let name: String
}

/// An immutable, parsed snapshot of one file version: per-line highlight tokens plus the syntax tree
/// for structural queries such as "which code block contains this line?".
///
/// Build it off the main thread with `SyntaxDocument.parse(lines:language:)`; afterwards it is safe to share.
public final class SyntaxDocument: Sendable {
    public let language: SyntaxLanguage?
    public let lineCount: Int
    private let tokens: [[SyntaxToken]]
    private let tree: Tree?
    private let lineFirstColumns: [Int]

    public static func parse(lines: [String], language: SyntaxLanguage?) async -> SyntaxDocument {
        await Task.detached(priority: .userInitiated) {
            SyntaxDocument(lines: lines, language: language)
        }.value
    }

    public init(lines: [String], language: SyntaxLanguage?) {
        self.language = language
        lineCount = lines.count
        lineFirstColumns = lines.map { line in line.utf16.firstIndex { $0 != 32 && $0 != 9 }.map { line.utf16.distance(from: line.utf16.startIndex, to: $0) } ?? 0 }

        guard let config = language?.configuration, let query = config.queries[.highlights] else {
            tokens = Array(repeating: [], count: lines.count)
            tree = nil
            return
        }
        let text = lines.joined(separator: "\n")
        let parser = Parser()
        guard (try? parser.setLanguage(config.language)) != nil, let mutable = parser.parse(text), let snapshot = mutable.copy() else {
            tokens = Array(repeating: [], count: lines.count)
            tree = nil
            return
        }
        tree = snapshot

        var starts: [Int] = []
        starts.reserveCapacity(lines.count)
        var offset = 0
        for line in lines { starts.append(offset); offset += line.utf16.count + 1 }

        var perLine = Array(repeating: [SyntaxToken](), count: lines.count)
        let highlights = query.execute(in: snapshot).resolve(with: .init(string: text)).highlights()
        for h in highlights {
            var loc = h.range.location
            let end = h.range.location + h.range.length
            guard end > loc else { continue }
            var line = Self.line(containing: loc, starts: starts)
            while loc < end && line < lines.count {
                let lineStart = starts[line]
                let lineEnd = lineStart + lines[line].utf16.count
                let a = loc - lineStart, b = min(end, lineEnd) - lineStart
                if b > a { perLine[line].append(SyntaxToken(range: a..<b, name: h.name)) }
                line += 1
                loc = lineEnd + 1
            }
        }
        tokens = perLine
    }

    private static func line(containing offset: Int, starts: [Int]) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Tokens for a 0-based line, ordered less-specific → more-specific (apply in order; later wins).
    public func tokens(line: Int) -> [SyntaxToken] {
        line >= 0 && line < tokens.count ? tokens[line] : []
    }

    /// The smallest named syntax node spanning more than one line that contains `line`
    /// (e.g. an `if`, a call, a function). Returns 0-based inclusive line bounds, or nil if
    /// nothing smaller than `maxLines` encloses it.
    public func enclosingBlock(line: Int, maxLines: Int = 80) -> ClosedRange<Int>? {
        guard let root = tree?.rootNode, line >= 0, line < lineCount else { return nil }
        let col = lineFirstColumns[line]
        let point = Point(row: line, column: col * 2) // tree-sitter columns are bytes; UTF-16 → ×2
        var node = root.descendant(in: point..<point)
        while let n = node, n.parent != nil {
            let r = n.pointRange
            let first = Int(r.lowerBound.row), last = Int(r.upperBound.row)
            if n.isNamed && last > first {
                return last - first + 1 <= maxLines ? first...last : nil
            }
            node = n.parent
        }
        return nil
    }
}

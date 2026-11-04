import Foundation
import RiviuDiff
import RiviuSyntax

/// A few lines of code from the indexed repository, to show in the hot path or a definition.
nonisolated struct CodeExcerpt: Identifiable, Hashable, Sendable {
    let path: String
    /// 0-based line of `lines[0]`.
    let firstLine: Int
    let lines: [String]
    /// 0-based lines this pull request added or changed, drawn tinted.
    let changedLines: Set<Int>
    /// The line to point at, like the call site. Open jumps here.
    let focusLine: Int?

    var id: String { "\(path):\(firstLine)" }
    var fileName: String { (path as NSString).lastPathComponent }
    var isChanged: Bool { (firstLine..<(firstLine + lines.count)).contains { changedLines.contains($0) } }
}

/// A function and some of its code, as the AI explanation of the hot path sees it.
struct HotPathItem: Identifiable, Hashable {
    let function: SymbolLocation?
    let title: String
    let excerpt: CodeExcerpt

    var id: String { excerpt.id + title }
}

/// One step of the hot path as shown: a function, and the part of it worth reading.
nonisolated struct HotPathStep: Identifiable, Hashable, Sendable {
    let function: SymbolLocation
    let excerpt: CodeExcerpt
    /// The 0-based line that calls the next step. nil on the last step.
    let callLine: Int?
    /// The lines the reviewer picked, on the step that holds them.
    let selectedLines: ClosedRange<Int>?

    var id: String { "\(function.path):\(function.lines.lowerBound)" }
    var title: String { "\(function.name)()" }
    /// Whether this pull request changed any of the function.
    var isChanged: Bool { function.lines.contains { excerpt.changedLines.contains($0) } }

    /// "order/E2eGrpcService.java:41": the file, its folder, and the line the function starts on.
    var shortLocation: String {
        let components = function.path.split(separator: "/")
        return components.suffix(2).joined(separator: "/") + ":\(function.lines.lowerBound + 1)"
    }
}

/// One path through the code, from where it starts to where it ends.
nonisolated struct HotPath: Hashable, Sendable {
    let steps: [HotPathStep]
    /// Which step holds the selected code.
    let focusIndex: Int
    /// The trace stopped going up or down at its depth limit, though there's more.
    let hasMoreAbove: Bool
    let hasMoreBelow: Bool

    var focus: HotPathStep { steps[focusIndex] }
}

/// Builds the hot path from the symbol index. Safe to run off the main thread.
nonisolated struct HotPathFinder: Sendable {
    let index: SymbolIndex
    /// 0-based changed head lines, for every file in the pull request.
    let changedLines: [String: Set<Int>]

    /// Most lines of a function shown in one step. Long functions show the part around the call.
    static let maxExcerptLines = 14

    /// The path through some lines of a file, or nil when there's no function in or near them.
    func hotPath(path: String, lines: ClosedRange<Int>) -> HotPath? {
        let tracer = CallTracer(index: index, changedLines: changedLines)
        guard let trace = tracer.trace(path: path, lines: lines) else { return nil }
        let steps = trace.steps.enumerated().map { offset, step in
            let isFocus = offset == trace.focusIndex
            let selection = isFocus && step.function.path == path ? lines : nil
            return makeStep(step.function, callLine: step.callLine, selection: selection)
        }
        return HotPath(steps: steps, focusIndex: trace.focusIndex, hasMoreAbove: trace.hasMoreAbove, hasMoreBelow: trace.hasMoreBelow)
    }

    private func makeStep(_ function: SymbolLocation, callLine: Int?, selection: ClosedRange<Int>?) -> HotPathStep {
        // Keep the selection and the call in view, or failing that the call.
        var anchors: [Int] = []
        if let selection { anchors += [selection.lowerBound, min(selection.upperBound, selection.lowerBound + 4)] }
        if let callLine { anchors.append(callLine) }
        let shown = Self.window(of: function.lines, around: anchors, callLine: callLine)
        let open = callLine ?? selection?.lowerBound ?? function.lines.lowerBound
        return HotPathStep(function: function, excerpt: excerpt(path: function.path, lines: shown, focus: open),
                           callLine: callLine, selectedLines: selection)
    }

    /// At most `maxExcerptLines` of a function: all of it if it's short, otherwise its start or the part
    /// around the anchors. If the anchors are too far apart, the call line wins.
    static func window(of function: ClosedRange<Int>, around anchors: [Int], callLine: Int?) -> ClosedRange<Int> {
        let limit = maxExcerptLines
        guard function.count > limit else { return function }
        var anchors = anchors.filter(function.contains)
        if let low = anchors.min(), let high = anchors.max(), high - low >= limit, let callLine {
            anchors = [callLine]
        }
        guard let low = anchors.min(), let high = anchors.max() else {
            return function.lowerBound...(function.lowerBound + limit - 1)
        }
        // A few lines of context before, the rest after.
        let spare = limit - (high - low + 1)
        var start = max(function.lowerBound, low - min(4, spare / 2))
        let end = min(function.upperBound, start + limit - 1)
        start = max(function.lowerBound, end - limit + 1)
        return start...end
    }

    func excerpt(path: String, lines: ClosedRange<Int>, focus: Int?) -> CodeExcerpt {
        let first = max(0, lines.lowerBound)
        let text = index.lines(first...max(first, lines.upperBound), of: path) ?? []
        return CodeExcerpt(path: path, firstLine: first, lines: text, changedLines: changedLines[path] ?? [], focusLine: focus)
    }
}

extension ReviewWorkspace {
    /// The changed head lines of every file in the pull request, by path. Files without a patch are
    /// included with no lines, so they still count as part of the pull request.
    var changedHeadLinesByPath: [String: Set<Int>] {
        var result: [String: Set<Int>] = [:]
        for file in pullRequest?.files ?? [] where file.status != .deleted {
            result[file.path] = changedHeadLines(inFileAt: file.path)
        }
        return result
    }
}

/// Hop descriptions already asked for, by pull request commit and path, so reopening the hot path doesn't ask again.
enum HotPathHopCache {
    static var descriptions: [String: [String]] = [:]

    static func key(headSHA: String, path: HotPath) -> String {
        ([headSHA] + path.steps.map(\.id)).joined(separator: "|")
    }
}

import Foundation
import RiviuAI
import RiviuDiff

/// One place the tour stops: a few lines of one file and why they matter.
nonisolated struct TourStop: Codable, Sendable, Hashable {
    let chapter: String
    let title: String
    let explanation: String
    let filePath: String
    let side: DiffSide
    /// 1-based, as in the diff.
    let lines: ClosedRange<Int>
    /// The diff of those lines, kept so the card doesn't need the file loaded.
    let excerpt: [PatchExcerpt.Line]

    var fileName: String { (filePath as NSString).lastPathComponent }
}

/// The few places in a pull request worth reading, in order, picked by the AI.
nonisolated struct ReviewTour: Codable, Sendable {
    let pullRequest: PullRequestReference
    /// Tours of older commits point at the wrong lines.
    let headSHA: String
    let stops: [TourStop]
    /// What the tour leaves out, in the AI's words.
    let rest: String
    /// Files the tour doesn't stop in.
    let skippedFileCount: Int

    /// Chapter names in tour order, each once.
    var chapters: [String] {
        var seen = Set<String>()
        return stops.map(\.chapter).filter { seen.insert($0).inserted }
    }

    /// The AI's stops that point at lines the diff really shows. Long ranges are cut to 30 lines.
    init(report: TourReport, pullRequest: PullRequest) {
        var stops: [TourStop] = []
        for stop in report.stops.prefix(TourReport.maxStops) {
            guard let file = pullRequest.file(at: stop.file), let patch = file.patch, stop.startLine > 0 else { continue }
            let side: DiffSide = stop.side == .old ? .base : .head
            let lines = stop.startLine...min(max(stop.startLine, stop.endLine), stop.startLine + 29)
            let excerpt = PatchExcerpt.lines(in: patch, side: side, range: lines)
            guard !excerpt.isEmpty else { continue }
            stops.append(TourStop(chapter: stop.chapter, title: stop.title, explanation: stop.explanation,
                                  filePath: file.path, side: side, lines: lines, excerpt: excerpt))
        }
        self.pullRequest = pullRequest.reference
        headSHA = pullRequest.headSHA
        self.stops = stops
        rest = report.rest ?? ""
        skippedFileCount = pullRequest.files.count - Set(stops.map(\.filePath)).count
    }
}

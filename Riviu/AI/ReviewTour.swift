import Foundation
import RiviuAI
import RiviuDiff

/// One place the tour stops: the first change of a hunk.
nonisolated struct TourStop: Codable, Sendable, Hashable {
    let filePath: String
    let side: DiffSide
    /// 0-based.
    let lineIndex: Int
    /// The hunk's first changed line, to recognise it by.
    let preview: String
}

nonisolated struct TourChapter: Codable, Sendable, Hashable {
    let title: String
    let why: String
    let stops: [TourStop]
    /// The chapter Riviu adds for hunks the AI left out, so nothing is skipped silently.
    var isNotCovered = false
}

/// A reading order for a pull request, in chapters, made by the AI.
nonisolated struct ReviewTour: Codable, Sendable {
    let pullRequest: PullRequestReference
    /// Tours of older commits point at the wrong lines.
    let headSHA: String
    let chapters: [TourChapter]

    var stopCount: Int { chapters.reduce(0) { $0 + $1.stops.count } }
}

/// Every hunk in a pull request, numbered H1, H2… so the AI can refer to them.
nonisolated struct TourHunks {
    let ids: [String]
    let stopsByID: [String: TourStop]
    /// "H1 Sources/App.swift line 12: let x = …", one hunk per line, for the prompt.
    let listing: String

    init(pullRequest: PullRequest) {
        var ids: [String] = []
        var stops: [String: TourStop] = [:]
        var listing: [String] = []
        for file in pullRequest.files {
            for hunk in PatchHunk.hunks(in: file.patch ?? "") {
                let id = "H\(ids.count + 1)"
                let side: DiffSide = hunk.firstAddedLine == nil ? .base : .head
                let line = hunk.firstAddedLine ?? hunk.firstRemovedLine ?? hunk.newStart
                let preview = hunk.changedLines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
                ids.append(id)
                stops[id] = TourStop(filePath: file.path, side: side, lineIndex: max(0, line - 1),
                                     preview: preview.trimmingCharacters(in: .whitespaces))
                let changed = hunk.changedLines.prefix(4).map { String($0.prefix(120)) }.joined(separator: " ⏎ ")
                listing.append("\(id) \(file.path) line \(line) (\(hunk.changedLines.count) changed lines): \(changed)")
            }
        }
        self.ids = ids
        stopsByID = stops
        self.listing = listing.joined(separator: "\n")
    }

    /// The AI's chapters, plus a "Not covered" chapter for any hunk it didn't place.
    func tour(from report: TourReport, pullRequest: PullRequest) -> ReviewTour {
        var used = Set<String>()
        var chapters: [TourChapter] = []
        for chapter in report.chapters {
            let stops = chapter.hunks.compactMap { id -> TourStop? in
                guard !used.contains(id), let stop = stopsByID[id] else { return nil }
                used.insert(id)
                return stop
            }
            if !stops.isEmpty {
                chapters.append(TourChapter(title: chapter.title, why: chapter.why, stops: stops))
            }
        }
        let left = ids.filter { !used.contains($0) }.compactMap { stopsByID[$0] }
        if !left.isEmpty {
            chapters.append(TourChapter(title: "Not covered", why: "Changes the tour didn't place. Check them so nothing is missed.",
                                        stops: left, isNotCovered: true))
        }
        return ReviewTour(pullRequest: pullRequest.reference, headSHA: pullRequest.headSHA, chapters: chapters)
    }
}

import Foundation
import RiviuDiff

/// Built-in example pull requests, for trying Riviu without signing in to GitHub.
nonisolated enum DemoPullRequests {
    static let all: [PullRequest] = [
        makePullRequest(
            number: 482,
            title: "Coalesce token refreshes and tidy the diff parser",
            author: "Mira Kovač",
            branch: "auth/refresh-coalescing",
            summary: "Only one token refresh runs at a time, the diff parser handles single-line hunks, and the legacy cache is removed. Adds a large generated fixture.",
            files: [DemoFiles.tokenStore, DemoFiles.diffParser, DemoFiles.oldCache].map(fileDiff) + [GeneratedFixture.fileDiff]
        ),
        makePullRequest(
            number: 479,
            title: "ETag caching and a review panel for the web client",
            author: "Oskar Lind",
            branch: "web/etag-cache",
            summary: "Pull request lists are cached with ETags, review submission errors are surfaced, and a new ReviewPanel component is added.",
            files: [DemoFiles.client, DemoFiles.reviewPanel, DemoFiles.config].map(fileDiff)
        ),
        makePullRequest(
            number: 471,
            title: "Webhook backpressure, paginated sync and diff-core tests",
            author: "Jules Romero",
            branch: "infra/webhook-backpressure",
            summary: "The webhook handler rejects events when its queue is full, review sync follows pagination, and diff-core gains tests.",
            files: [DemoFiles.syncReviews, DemoFiles.webhook, DemoFiles.diffCore, DemoFiles.architecture].map(fileDiff)
        ),
    ]

    static func pullRequest(number: Int) -> PullRequest? {
        all.first { $0.number == number }
    }

    /// The full diff of a demo file, by path.
    static func fileDiff(at path: String) -> FileDiff? {
        fileDiffsByPath[path]
    }

    static let findings: [ReviewFinding] = {
        let demoFiles = [DemoFiles.tokenStore, DemoFiles.diffParser, DemoFiles.oldCache, DemoFiles.client, DemoFiles.reviewPanel,
                         DemoFiles.config, DemoFiles.syncReviews, DemoFiles.webhook, DemoFiles.diffCore, DemoFiles.architecture]
        return demoFiles.flatMap(findings(in:)) + GeneratedFixture.findings
    }()

    private static let fileDiffsByPath: [String: FileDiff] = {
        let allDiffs = [DemoFiles.tokenStore, DemoFiles.diffParser, DemoFiles.oldCache, DemoFiles.client, DemoFiles.reviewPanel,
                        DemoFiles.config, DemoFiles.syncReviews, DemoFiles.webhook, DemoFiles.diffCore, DemoFiles.architecture]
            .map(fileDiff) + [GeneratedFixture.fileDiff]
        return Dictionary(uniqueKeysWithValues: allDiffs.map { ($0.path, $0) })
    }()

    private static func makePullRequest(number: Int, title: String, author: String, branch: String, summary: String,
                                        files: [FileDiff]) -> PullRequest {
        let changedFiles = files.map { diff in
            ChangedFile(path: diff.path, previousPath: nil, status: diff.status, additions: diff.additions,
                        deletions: diff.deletions, patch: UnifiedDiffText.make(for: diff))
        }
        return PullRequest(reference: PullRequestReference(repository: PullRequestReference.demoRepository, number: number),
                           title: title, author: author, headBranch: branch, baseBranch: "main", summary: summary,
                           headSHA: "", baseSHA: "", webURL: nil, files: changedFiles)
    }

    private static func fileDiff(_ file: DemoFile) -> FileDiff {
        FileDiff(path: file.path, status: file.status,
                 baseLines: FileDiff.lines(of: file.status == .added ? "" : file.base),
                 headLines: FileDiff.lines(of: file.head))
    }

    /// Demo findings name a snippet of code; this finds the line it's on.
    private static func findings(in file: DemoFile) -> [ReviewFinding] {
        let diff = fileDiff(file)
        return file.findings.enumerated().compactMap { number, finding in
            guard let line = diff.lines(on: finding.side).firstIndex(where: { $0.contains(finding.match) }) else { return nil }
            return ReviewFinding(id: "\(file.path)#\(number)", filePath: file.path, side: finding.side, lineIndex: line,
                                 title: finding.title, body: finding.body, severity: finding.severity)
        }
    }
}

/// A 10,000-line file with scattered edits, to keep scrolling performance honest.
nonisolated enum GeneratedFixture {
    static let path = "Tests/Fixtures/GeneratedFixture.swift"

    static let fileDiff: FileDiff = {
        var random = SeededRandom(seed: 42)
        let base = codeLines(count: 10_000, random: &random)
        let head = edited(base, random: &random)
        return FileDiff(path: path, status: .modified, baseLines: base, headLines: head)
    }()

    static let findings: [ReviewFinding] = {
        var findings: [ReviewFinding] = []
        var changeNumber = 0
        for case let .changed(_, added) in fileDiff.segments where !added.isEmpty {
            if changeNumber % 9 == 4 {
                findings.append(ReviewFinding(id: "fixture#\(changeNumber)", filePath: path, side: .head, lineIndex: added.upperBound - 1,
                                              title: "Value may be read before it is assigned",
                                              body: "On this path `value` is read before the branch above assigns it.",
                                              severity: .medium))
            }
            changeNumber += 1
        }
        return findings
    }()

    private static let words = ["token", "session", "request", "review", "cache", "diff", "hunk", "file", "index", "result",
                                "value", "item", "user", "config", "state", "buffer", "range", "offset", "line", "path"]
    private static let types = ["String", "Int", "Bool", "URL", "Data", "ReviewThread", "DiffHunk", "PullRequest", "[String]"]

    private static func codeLines(count: Int, random: inout SeededRandom) -> [String] {
        var lines: [String] = []
        var depth = 0
        while lines.count < count {
            let indent = String(repeating: "    ", count: depth)
            if depth == 0 {
                lines.append("")
                lines.append("// \(sentence(&random))")
                lines.append("func \(name(&random))(\(random.pick(words)): \(random.pick(types))) -> \(random.pick(types)) {")
                depth = 1
            } else if random.chance(0.12) {
                depth -= 1
                lines.append(String(repeating: "    ", count: depth) + "}")
            } else if depth < 3 && random.chance(0.1) {
                lines.append(indent + "if \(random.pick(words)).\(random.pick(words)) > \(random.int(below: 500)) {")
                depth += 1
            } else {
                lines.append(indent + statement(&random))
            }
        }
        while depth > 0 {
            depth -= 1
            lines.append(String(repeating: "    ", count: depth) + "}")
        }
        return lines
    }

    private static func edited(_ base: [String], random: inout SeededRandom) -> [String] {
        var head: [String] = []
        var index = 0
        while index < base.count {
            if random.chance(0.02) {
                let replacedCount = min(random.int(below: 4), base.count - index)
                for offset in 0..<replacedCount {
                    head.append(base[index + offset] + " // \(random.pick(words))")
                }
                for _ in 0..<random.int(below: 3) {
                    head.append("    " + statement(&random))
                }
                index += replacedCount
            }
            if index < base.count {
                head.append(base[index])
                index += 1
            }
        }
        return head
    }

    private static func name(_ random: inout SeededRandom) -> String {
        random.pick(words) + random.pick(words).capitalized
    }

    private static func sentence(_ random: inout SeededRandom) -> String {
        (0..<(4 + random.int(below: 5))).map { _ in random.pick(words) }.joined(separator: " ")
    }

    private static func statement(_ random: inout SeededRandom) -> String {
        switch random.int(below: 6) {
        case 0: "let \(name(&random)) = \(random.pick(words)).\(name(&random))(\(random.int(below: 1000)))"
        case 1: "// \(sentence(&random))"
        case 2: "guard let \(random.pick(words)) = \(name(&random)) else { return nil }"
        case 3: "var \(name(&random)): \(random.pick(types)) = \"\(sentence(&random))\""
        case 4: "\(random.pick(words)).\(name(&random)) += \(random.int(below: 64))"
        default: "return \(name(&random))(\(random.pick(words)), \(random.pick(words)): \(random.int(below: 10)))"
        }
    }
}

/// A tiny deterministic random number generator (SplitMix64), so the fixture is the same on every launch.
nonisolated struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(below upperBound: Int) -> Int {
        Int(next() % UInt64(upperBound))
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double(next() % 10_000) / 10_000 < probability
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[int(below: items.count)]
    }
}

import Foundation
import Observation
import RiviuAI
import RiviuDiff
import RiviuGitHub

/// An AI review of one pull request at one commit: a summary, an overall risk and line-level findings.
nonisolated struct AIReview: Codable, Sendable {
    let pullRequest: PullRequestReference
    /// The commit that was reviewed. Newer commits make the review outdated.
    let headSHA: String
    let createdAt: Date
    /// Which provider and model wrote it, like "Claude Code · opus".
    let author: String
    let summary: String
    let risk: ReviewFinding.Severity
    var findings: [ReviewFinding]
    /// The repository's guideline files the review followed, like "CLAUDE.md".
    var guidelineFiles: [String]?
    var specCheck: ReviewReport.SpecCheck?
    var questions: [AuthorQuestion]?
}

/// Something only the author can answer, which the reviewer can ask as a comment.
nonisolated struct AuthorQuestion: Codable, Sendable, Identifiable, Hashable {
    let filePath: String
    /// 0-based, in the new file.
    let lineIndex: Int
    let question: String

    var id: String { "\(filePath):\(lineIndex):\(question)" }
}

/// AI reviews, saved to disk so a review run in the background is ready when its pull request is opened.
@Observable
final class AIReviewStore {
    enum Activity: Equatable {
        /// Waiting for other reviews to finish first.
        case queued
        case reviewing(author: String)
        case failed(String)
    }

    private(set) var reviews: [PullRequestReference: AIReview] = [:]
    /// Pull requests whose review is running, or failed last time.
    private(set) var activities: [PullRequestReference: Activity] = [:]

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let account: GitHubAccount
    @ObservationIgnored private let rules: ReviewRuleStore
    @ObservationIgnored private let fileURL = URL.applicationSupportDirectory.appending(path: "Riviu/ai-reviews.json")

    init(settings: AppSettings, account: GitHubAccount, rules: ReviewRuleStore, demoReviews: [AIReview]) {
        self.settings = settings
        self.account = account
        self.rules = rules
        load()
        for review in demoReviews {
            reviews[review.pullRequest] = review
        }
    }

    func review(for reference: PullRequestReference) -> AIReview? {
        reviews[reference]
    }

    func activity(for reference: PullRequestReference) -> Activity? {
        activities[reference]
    }

    func isReviewing(_ reference: PullRequestReference) -> Bool {
        if case .reviewing = activities[reference] { return true }
        return false
    }

    /// Shows that a review is coming, before it starts.
    func queue(_ reference: PullRequestReference) {
        if !isReviewing(reference) {
            activities[reference] = .queued
        }
    }

    /// Starts a review without waiting for it, for the Run AI Review button.
    func start(for pullRequest: PullRequest) {
        Task { await run(for: pullRequest) }
    }

    /// Skips pull requests that were already reviewed at their latest commit.
    func runIfNeeded(for pullRequest: PullRequest) async {
        if review(for: pullRequest.reference)?.headSHA == pullRequest.headSHA {
            activities[pullRequest.reference] = nil
            return
        }
        await run(for: pullRequest)
    }

    /// For a queued review that can't run, for example because the pull request didn't load.
    func fail(_ reference: PullRequestReference, message: String) {
        activities[reference] = .failed(message)
    }

    func run(for pullRequest: PullRequest) async {
        let reference = pullRequest.reference
        guard !isReviewing(reference) else { return }
        let author = AISetup.description(of: .review, settings: settings)
        activities[reference] = .reviewing(author: author)
        do {
            let provider = try AISetup.makeProvider(for: .review, settings: settings)
            async let fetchedGuidelines = account.loader.repositoryGuidelines(for: pullRequest)
            async let linkedIssues = account.loader.linkedIssues(for: pullRequest)
            async let previous = previousReview(for: pullRequest)
            let guidelines = await fetchedGuidelines
            let earlier = await previous
            let request = ReviewPrompts.reviewRequest(instructions: settings.reviewInstructions, pullRequest: pullRequest,
                                                      guidelines: guidelines, linkedIssues: await linkedIssues, previous: earlier,
                                                      rules: rules.rules(for: reference.repository))
            let report = try ReviewReport.parse(try await provider.reply(to: request))
            var review = AIReview(pullRequest: pullRequest, report: report, author: author)
            if let earlier {
                review.findings = carriedOver(earlier.findings, report: report, pullRequest: pullRequest) + review.findings
            }
            review.guidelineFiles = guidelines.map(\.path)
            reviews[reference] = review
            activities[reference] = nil
            save()
        } catch {
            activities[reference] = .failed(error.localizedDescription)
        }
    }

    /// The last review's open findings and what changed since, when the pull request has new commits.
    private func previousReview(for pullRequest: PullRequest) async -> PreviousReview? {
        guard let earlier = reviews[pullRequest.reference], earlier.headSHA != pullRequest.headSHA, !pullRequest.reference.isDemo,
              let client = account.client else { return nil }
        let open = earlier.findings.filter { !$0.isAddressed }
        guard !open.isEmpty,
              let comparison = try? await client.compare(repository: pullRequest.reference.repository, base: earlier.headSHA,
                                                         head: pullRequest.headSHA),
              comparison.status == "ahead" else { return nil }
        let changedFiles = (comparison.files ?? []).map(PullRequestLoader.changedFile)
        return PreviousReview(findings: open, changedFiles: changedFiles)
    }

    /// Earlier findings the AI says are still open move to their new line; fixed ones are kept, marked as addressed.
    private func carriedOver(_ earlier: [ReviewFinding], report: ReviewReport, pullRequest: PullRequest) -> [ReviewFinding] {
        let outcomes = Dictionary((report.previousFindings ?? []).map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        return earlier.enumerated().compactMap { index, finding in
            var finding = finding
            switch outcomes[index] {
            case let outcome? where outcome.status == .addressed:
                finding.addressedInSHA = pullRequest.headSHA
            case let outcome?:
                guard let line = outcome.line, line > 0 else { return nil }
                finding = ReviewFinding(id: finding.id, filePath: finding.filePath, side: .head, lineIndex: line - 1,
                                        title: finding.title, body: finding.body, severity: finding.severity)
            case nil:
                // The AI didn't say; its old line number can't be trusted on the new commit.
                return nil
            }
            return finding
        }
    }

    func dismissFinding(_ id: String, in reference: PullRequestReference) {
        reviews[reference]?.findings.removeAll { $0.id == id }
        save()
    }

    // MARK: - Saving

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([AIReview].self, from: data) else { return }
        for review in saved {
            reviews[review.pullRequest] = review
        }
    }

    private func save() {
        let saved = reviews.values.filter { !$0.pullRequest.isDemo }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(saved)).write(to: fileURL, options: .atomic)
        } catch {
            print("Couldn't save AI reviews: \(error)")
        }
    }
}

extension AIReview {
    /// Keeps only findings on files in the pull request.
    init(pullRequest: PullRequest, report: ReviewReport, author: String) {
        self.pullRequest = pullRequest.reference
        headSHA = pullRequest.headSHA
        createdAt = .now
        self.author = author
        summary = report.summary
        risk = ReviewFinding.Severity(report.risk)
        specCheck = report.specCheck
        questions = (report.questions ?? []).prefix(3).compactMap { question in
            guard pullRequest.file(at: question.file) != nil, question.line > 0 else { return nil }
            return AuthorQuestion(filePath: question.file, lineIndex: question.line - 1, question: question.question)
        }
        findings = report.findings.enumerated().compactMap { number, finding in
            guard let file = pullRequest.file(at: finding.file), finding.line > 0 else { return nil }
            var result = ReviewFinding(id: "\(pullRequest.headSHA):\(number)", filePath: finding.file,
                                       side: finding.side == .old ? .base : .head, lineIndex: finding.line - 1,
                                       title: finding.title, body: finding.body, severity: ReviewFinding.Severity(finding.severity))
            if Self.canSuggest(finding, in: file) {
                result.endLineIndex = (finding.endLine ?? finding.line) - 1
                result.suggestion = finding.suggestion
            }
            return result
        }
    }

    /// GitHub only takes a suggestion on new-file lines inside one hunk, so anything else is dropped.
    private static func canSuggest(_ finding: ReviewReport.Finding, in file: ChangedFile) -> Bool {
        guard finding.suggestion != nil, finding.side == .new, let patch = file.patch else { return false }
        let lines = finding.line...max(finding.line, finding.endLine ?? finding.line)
        return NumberedPatch.newLineRanges(in: patch).contains { $0.contains(lines.lowerBound) && $0.contains(lines.upperBound) }
    }
}

extension ReviewFinding.Severity {
    init(_ level: ReviewReport.Level) {
        switch level {
        case .high: self = .high
        case .medium: self = .medium
        case .low: self = .low
        }
    }
}

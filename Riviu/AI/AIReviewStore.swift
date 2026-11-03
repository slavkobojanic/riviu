import Foundation
import Observation
import RiviuAI
import RiviuDiff

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
    @ObservationIgnored private let fileURL = URL.applicationSupportDirectory.appending(path: "Riviu/ai-reviews.json")

    init(settings: AppSettings, demoReviews: [AIReview]) {
        self.settings = settings
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
            let request = ReviewPrompts.reviewRequest(instructions: settings.reviewInstructions, pullRequest: pullRequest)
            let report = try ReviewReport.parse(try await provider.reply(to: request))
            reviews[reference] = AIReview(pullRequest: pullRequest, report: report, author: author)
            activities[reference] = nil
            save()
        } catch {
            activities[reference] = .failed(error.localizedDescription)
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
        findings = report.findings.enumerated().compactMap { number, finding in
            guard pullRequest.file(at: finding.file) != nil, finding.line > 0 else { return nil }
            return ReviewFinding(id: "\(pullRequest.headSHA):\(number)", filePath: finding.file,
                                 side: finding.side == .old ? .base : .head, lineIndex: finding.line - 1,
                                 title: finding.title, body: finding.body, severity: ReviewFinding.Severity(finding.severity))
        }
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

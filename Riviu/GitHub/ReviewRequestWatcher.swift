import Foundation
import Observation
import RiviuGitHub

/// Checks GitHub every few minutes for pull requests that newly request your review. For each one it posts a
/// notification and, if turned on, runs an AI review so the summary is ready when you open it.
@Observable
final class ReviewRequestWatcher {
    /// Open pull requests waiting for your review, newest activity first.
    private(set) var requests: [GitHubPullRequestSummary] = []
    private(set) var isChecking = false
    private(set) var lastChecked: Date?
    private(set) var errorMessage: String?

    @ObservationIgnored private let account: GitHubAccount
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let aiReviews: AIReviewStore
    @ObservationIgnored private let inbox: PullRequestInbox
    @ObservationIgnored private let notifications: ReviewRequestNotifications
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var reviewQueue: [(GitHubPullRequestSummary, PullRequestReference)] = []
    @ObservationIgnored private var isWorkingThroughQueue = false

    init(account: GitHubAccount, settings: AppSettings, aiReviews: AIReviewStore, inbox: PullRequestInbox,
         notifications: ReviewRequestNotifications) {
        self.account = account
        self.settings = settings
        self.aiReviews = aiReviews
        self.inbox = inbox
        self.notifications = notifications
    }

    func start() {
        guard loop == nil else { return }
        loop = Task {
            if settings.notifiesAboutReviewRequests {
                await notifications.requestPermission()
            }
            while !Task.isCancelled {
                // Sign-in finishes after launch; check as soon as it does.
                guard account.isSignedIn else {
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }
                if settings.checksForReviewRequests {
                    await checkNow()
                }
                try? await Task.sleep(for: .seconds(60 * max(1, settings.reviewRequestCheckMinutes)))
            }
        }
    }

    /// Refreshes the pull request list and checks for new review requests, for the Refresh button and ⌘R.
    func refreshAll() {
        inbox.refresh()
        Task { await checkNow() }
    }

    func checkNow() async {
        guard let client = account.client, let login = account.user?.login, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            requests = try await client.searchPullRequests(PullRequestQuery()) // open, review requested from me
            errorMessage = nil
            await account.repositories.prefetch(requests, client: client)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        lastChecked = .now

        let current = requests.map { PullRequestReference(repository: $0.repository, number: $0.number) }
        let seenKey = "reviewRequestsSeen.\(login)"
        let seen = UserDefaults.standard.stringArray(forKey: seenKey)
        UserDefaults.standard.set(current.map(\.id), forKey: seenKey)

        // The first check only remembers what's already waiting, so you aren't flooded with old requests.
        guard let seen else { return }
        let newRequests = zip(requests, current).filter { !seen.contains($0.1.id) }
        guard !newRequests.isEmpty else { return }

        inbox.refresh()
        for (summary, reference) in newRequests {
            if settings.notifiesAboutReviewRequests {
                notifications.post(title: "Review requested", body: notificationText(for: summary), about: reference)
            }
            if settings.reviewsNewRequestsWithAI {
                aiReviews.queue(reference)
                reviewQueue.append((summary, reference))
            }
        }
        Task { await workThroughReviewQueue() }
    }

    // MARK: - AI reviews of new requests

    /// One review at a time, so a burst of requests doesn't start several AI runs at once.
    private func workThroughReviewQueue() async {
        guard !isWorkingThroughQueue else { return }
        isWorkingThroughQueue = true
        while !reviewQueue.isEmpty {
            let (summary, reference) = reviewQueue.removeFirst()
            await review(summary, reference: reference)
        }
        isWorkingThroughQueue = false
    }

    private func review(_ summary: GitHubPullRequestSummary, reference: PullRequestReference) async {
        do {
            let pullRequest = try await account.loader.pullRequest(reference)
            await aiReviews.runIfNeeded(for: pullRequest)
        } catch {
            aiReviews.fail(reference, message: error.localizedDescription)
            return
        }
        guard settings.notifiesAboutReviewRequests, let review = aiReviews.review(for: reference) else { return }
        let findings = review.findings.count == 1 ? "1 finding" : "\(review.findings.count) findings"
        notifications.post(title: "Review requested, \(review.risk.rawValue) risk",
                           body: "\(notificationText(for: summary))\nAI summary ready, \(findings).",
                           about: reference, playsSound: false)
    }

    private func notificationText(for summary: GitHubPullRequestSummary) -> String {
        "\(summary.title) — from \(summary.user.login)"
    }
}

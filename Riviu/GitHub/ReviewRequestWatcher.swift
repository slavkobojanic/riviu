import Foundation
import Observation
import RiviuGitHub

/// Checks GitHub every few minutes for pull requests that newly request your review. For each one it posts a
/// notification. If turned on, it also runs an AI review of every waiting request that doesn't have one, so the
/// summary is ready when you open it.
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
    /// `isNew` is false for requests that were already waiting, which don't get a notification when reviewed.
    @ObservationIgnored private var reviewQueue: [(summary: GitHubPullRequestSummary, reference: PullRequestReference, isNew: Bool)] = []
    @ObservationIgnored private var runningReviews = 0
    /// Reviews run side by side, up to this many. Each one is a CLI process or an API request, and providers
    /// rate-limit, so a backlog of 30 requests doesn't start 30 at once.
    private static let maxConcurrentReviews = 4

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

        // The first check only remembers what's already waiting, so you aren't notified about old requests.
        let newRequests = seen.map { seen in zip(requests, current).filter { !seen.contains($0.1.id) } } ?? []
        if !newRequests.isEmpty {
            inbox.refresh()
        }
        if settings.notifiesAboutReviewRequests {
            for (summary, reference) in newRequests {
                notifications.post(title: "Review requested", body: notificationText(for: summary), about: reference)
            }
        }

        guard settings.reviewsNewRequestsWithAI else { return }
        for (summary, reference) in zip(requests, current) {
            let isNew = newRequests.contains { $0.1 == reference }
            // A request that has never been reviewed, and isn't being reviewed or failed already.
            let neverReviewed = aiReviews.review(for: reference) == nil && aiReviews.activity(for: reference) == nil
            guard isNew || neverReviewed, !reviewQueue.contains(where: { $0.reference == reference }) else { continue }
            aiReviews.queue(reference)
            reviewQueue.append((summary, reference, isNew))
        }
        startQueuedReviews()
    }

    // MARK: - AI reviews of new requests

    /// Starts queued reviews until `maxConcurrentReviews` are running. Each one starts the next when it finishes.
    private func startQueuedReviews() {
        while runningReviews < Self.maxConcurrentReviews, !reviewQueue.isEmpty {
            let next = reviewQueue.removeFirst()
            runningReviews += 1
            Task {
                await review(next.summary, reference: next.reference, notifies: next.isNew)
                runningReviews -= 1
                startQueuedReviews()
            }
        }
    }

    private func review(_ summary: GitHubPullRequestSummary, reference: PullRequestReference, notifies: Bool) async {
        do {
            let pullRequest = try await account.loader.pullRequest(reference)
            await aiReviews.runIfNeeded(for: pullRequest)
        } catch {
            aiReviews.fail(reference, message: error.localizedDescription)
            return
        }
        guard notifies, settings.notifiesAboutReviewRequests, let review = aiReviews.review(for: reference) else { return }
        let findings = review.findings.count == 1 ? "1 finding" : "\(review.findings.count) findings"
        notifications.post(title: "Review requested, \(review.risk.rawValue) risk",
                           body: "\(notificationText(for: summary))\nAI summary ready, \(findings).",
                           about: reference, playsSound: false)
    }

    private func notificationText(for summary: GitHubPullRequestSummary) -> String {
        "\(summary.title) — from \(summary.user.login)"
    }
}

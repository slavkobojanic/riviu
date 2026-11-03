import Foundation
import Observation
import RiviuGitHub

/// Checks GitHub every few minutes for pull requests that newly request your review. For each one it posts a
/// notification and, if turned on, runs an AI review so the summary is ready when you open it.
@Observable
final class ReviewRequestWatcher {
    private(set) var lastChecked: Date?
    private(set) var errorMessage: String?

    @ObservationIgnored private let account: GitHubAccount
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let aiReviews: AIReviewStore
    @ObservationIgnored private let inbox: PullRequestInbox
    @ObservationIgnored private let notifications: ReviewRequestNotifications
    @ObservationIgnored private var loop: Task<Void, Never>?

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

    func checkNow() async {
        guard let client = account.client, let login = account.user?.login else { return }
        let requests: [GitHubPullRequestSummary]
        do {
            requests = try await client.searchPullRequests(PullRequestQuery()) // open, review requested from me
            errorMessage = nil
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
            await handleNewRequest(summary, reference: reference)
        }
    }

    private func handleNewRequest(_ summary: GitHubPullRequestSummary, reference: PullRequestReference) async {
        let description = "\(summary.title) — from \(summary.user.login)"
        if settings.notifiesAboutReviewRequests {
            notifications.post(title: "Review requested", body: description, about: reference)
        }
        guard settings.reviewsNewRequestsWithAI,
              let pullRequest = try? await account.loader.pullRequest(reference) else { return }

        await aiReviews.runIfNeeded(for: pullRequest)
        guard settings.notifiesAboutReviewRequests, let review = aiReviews.review(for: reference) else { return }
        let findings = review.findings.count == 1 ? "1 finding" : "\(review.findings.count) findings"
        notifications.post(title: "Review requested · \(review.risk.rawValue) risk",
                           body: "\(description)\nAI summary ready, \(findings).", about: reference, playsSound: false)
    }
}

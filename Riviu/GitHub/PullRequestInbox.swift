import Foundation
import Observation
import RiviuGitHub

/// The pull request list in the sidebar: the filters and the results of searching GitHub with them.
@Observable
final class PullRequestInbox {
    var query: PullRequestQuery {
        didSet {
            guard query != oldValue else { return }
            saveQuery()
            refresh()
        }
    }

    private(set) var pullRequests: [GitHubPullRequestSummary] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Repositories seen in results, offered in the repository filter.
    private(set) var knownRepositories: [String]

    @ObservationIgnored private let account: GitHubAccount
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(account: GitHubAccount) {
        self.account = account
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "inboxQuery"), let saved = try? JSONDecoder().decode(PullRequestQuery.self, from: data) {
            query = saved
        } else {
            query = PullRequestQuery()
        }
        knownRepositories = defaults.stringArray(forKey: "knownRepositories") ?? []
    }

    func refresh() {
        guard let client = account.client else {
            pullRequests = []
            return
        }
        searchTask?.cancel()
        isLoading = true
        let query = query
        searchTask = Task {
            do {
                let results = try await client.searchPullRequests(query)
                guard !Task.isCancelled else { return }
                pullRequests = results
                errorMessage = nil
                remember(repositories: results.map(\.repository))
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func remember(repositories: [String]) {
        let merged = Set(knownRepositories).union(repositories)
        knownRepositories = merged.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        UserDefaults.standard.set(knownRepositories, forKey: "knownRepositories")
    }

    private func saveQuery() {
        if let data = try? JSONEncoder().encode(query) {
            UserDefaults.standard.set(data, forKey: "inboxQuery")
        }
    }
}

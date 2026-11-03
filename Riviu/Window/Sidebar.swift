import SwiftUI

/// The left column: the pull request list, or the files of the open pull request.
struct Sidebar: View {
    let workspace: ReviewWorkspace
    let inbox: PullRequestInbox
    let account: GitHubAccount
    let aiReviews: AIReviewStore
    let watcher: ReviewRequestWatcher
    @State private var page: Page

    enum Page {
        case pullRequests
        case files
    }

    /// Reopening the window shows the open pull request's files.
    init(workspace: ReviewWorkspace, inbox: PullRequestInbox, account: GitHubAccount, aiReviews: AIReviewStore,
         watcher: ReviewRequestWatcher) {
        self.workspace = workspace
        self.inbox = inbox
        self.account = account
        self.aiReviews = aiReviews
        self.watcher = watcher
        _page = State(initialValue: workspace.pullRequest == nil && workspace.loadingReference == nil ? .pullRequests : .files)
    }

    var body: some View {
        Group {
            switch page {
            case .pullRequests:
                PullRequestList(inbox: inbox, account: account, workspace: workspace, aiReviews: aiReviews) { reference in
                    workspace.open(reference)
                    page = .files
                }
            case .files:
                FileSidebar(workspace: workspace, aiReviews: aiReviews) { page = .pullRequests }
                    .id(workspace.pullRequest?.id) // fresh folder expansion for each pull request
            }
        }
        .toolbar {
            ToolbarItem {
                RefreshButton(inbox: inbox, watcher: watcher)
            }
        }
        .onChange(of: workspace.loadingReference) { _, reference in
            // Opening a pull request from elsewhere (like chat history) shows its files.
            if reference != nil { page = .files }
        }
    }
}

/// Refreshes the pull request list and checks for new review requests. Spins while either is running.
struct RefreshButton: View {
    let inbox: PullRequestInbox
    let watcher: ReviewRequestWatcher

    var body: some View {
        Button { watcher.refreshAll() } label: {
            if inbox.isLoading || watcher.isChecking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .help("Refresh pull requests and check for new review requests (⌘R)")
    }
}

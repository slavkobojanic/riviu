import SwiftUI

/// The left column: the pull request list, or the files of the open pull request.
struct Sidebar: View {
    let workspace: ReviewWorkspace
    let inbox: PullRequestInbox
    let account: GitHubAccount
    let aiReviews: AIReviewStore
    let watcher: ReviewRequestWatcher

    var body: some View {
        Group {
            // The workspace holds the page, so the Review menu can switch it too.
            switch workspace.sidebarPage {
            case .pullRequests:
                PullRequestList(inbox: inbox, account: account, workspace: workspace, aiReviews: aiReviews) { reference in
                    workspace.open(reference)
                }
            case .files:
                FileSidebar(workspace: workspace, aiReviews: aiReviews) { workspace.showPullRequestList() }
                    .id(workspace.pullRequest?.id) // fresh folder expansion for each pull request
            }
        }
        .toolbar {
            ToolbarItem {
                RefreshButton(inbox: inbox, watcher: watcher)
            }
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

import SwiftUI

/// The left column: the pull request list, or the files of the open pull request.
struct Sidebar: View {
    let workspace: ReviewWorkspace
    let inbox: PullRequestInbox
    let account: GitHubAccount
    @State private var page = Page.pullRequests

    enum Page {
        case pullRequests
        case files
    }

    var body: some View {
        Group {
            switch page {
            case .pullRequests:
                PullRequestList(inbox: inbox, account: account, workspace: workspace) { reference in
                    workspace.open(reference)
                    page = .files
                }
            case .files:
                FileSidebar(workspace: workspace) { page = .pullRequests }
                    .id(workspace.pullRequest?.id) // fresh folder expansion for each pull request
            }
        }
        .onChange(of: workspace.loadingReference) { _, reference in
            // Opening a pull request from elsewhere (like chat history) shows its files.
            if reference != nil { page = .files }
        }
    }
}

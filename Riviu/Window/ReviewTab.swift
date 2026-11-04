import RiviuGitHub
import RiviuMarkdown
import SwiftUI

/// One tab: a review window with its own workspace. It remembers its pull request, so tabs come back after a relaunch.
struct ReviewTab: View {
    let tabs: ReviewTabs
    let inbox: PullRequestInbox
    let account: GitHubAccount
    let chats: ChatStore
    let aiReviews: AIReviewStore
    let watcher: ReviewRequestWatcher
    let settings: AppSettings

    @State private var workspace: ReviewWorkspace?
    @SceneStorage("openPullRequest") private var savedPullRequest = ""
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let workspace {
                ReviewWindow(workspace: workspace, inbox: inbox, account: account, chats: chats, aiReviews: aiReviews,
                             watcher: watcher, settings: settings)
                    .background {
                        WindowObserver { window in
                            tabs.register(workspace, window: window)
                        } onBecomeKey: {
                            tabs.didBecomeKey(workspace)
                        } onClose: {
                            tabs.didClose(workspace)
                        }
                    }
                    .onChange(of: workspace.pullRequest?.reference) { _, reference in
                        savedPullRequest = reference?.id ?? ""
                    }
            }
        }
        .environment(tabs)
        // Images in descriptions and comments, which in private repositories need the token.
        .textual.imageAttachmentLoader(GitHubImageLoader(token: account.client?.token))
        .onAppear {
            tabs.remember(openWindow)
            // Picked once: SwiftUI can make this view several times, but onAppear only runs when it's shown.
            guard workspace == nil else { return }
            let new = tabs.workspaceForNewWindow()
            if new.pullRequest == nil, new.loadingReference == nil, let reference = PullRequestReference(id: savedPullRequest) {
                new.open(reference)
            }
            workspace = new
        }
    }
}

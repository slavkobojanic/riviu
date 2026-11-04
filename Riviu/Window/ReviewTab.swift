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
    @State private var timesShown = 0
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
                        } onShow: {
                            timesShown += 1
                        } onClose: {
                            tabs.didClose(workspace)
                        }
                    }
                    // Switching tabs swaps windows at once, so the tab's content fades up to show it changed.
                    .phaseAnimator([true, false], trigger: timesShown) { content, isSettled in
                        content
                            .opacity(isSettled ? 1 : 0.25)
                            .offset(y: isSettled ? 0 : 6)
                    } animation: { isSettled in
                        isSettled ? .easeOut(duration: 0.22) : nil
                    }
                    .onChange(of: workspace.pullRequest?.reference) { _, reference in
                        savedPullRequest = reference?.id ?? ""
                    }
            }
        }
        .environment(tabs)
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

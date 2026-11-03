import SwiftUI

@main
struct RiviuApp: App {
    @State private var settings: AppSettings
    @State private var account: GitHubAccount
    @State private var inbox: PullRequestInbox
    @State private var workspace: ReviewWorkspace
    @State private var chats: ChatStore
    @State private var aiReviews: AIReviewStore
    @State private var watcher: ReviewRequestWatcher
    private let notifications = ReviewRequestNotifications()

    init() {
        let settings = AppSettings()
        let account = GitHubAccount()
        _settings = State(initialValue: settings)
        _account = State(initialValue: account)
        let inbox = PullRequestInbox(account: account)
        let aiReviews = AIReviewStore(settings: settings, demoReviews: DemoPullRequests.reviews)
        let workspace = ReviewWorkspace(settings: settings, account: account, aiReviews: aiReviews)
        let watcher = ReviewRequestWatcher(account: account, settings: settings, aiReviews: aiReviews, inbox: inbox,
                                           notifications: notifications)
        _inbox = State(initialValue: inbox)
        _aiReviews = State(initialValue: aiReviews)
        _workspace = State(initialValue: workspace)
        _watcher = State(initialValue: watcher)
        _chats = State(initialValue: ChatStore(makeProvider: { try AISetup.makeProvider(for: .chat, settings: settings) }))

        notifications.onOpen = { workspace.open($0) }
        watcher.start()
    }

    var body: some Scene {
        Window("Riviu", id: "review") {
            ReviewWindow(workspace: workspace, inbox: inbox, account: account, chats: chats, aiReviews: aiReviews, settings: settings)
        }
        .defaultSize(width: 1500, height: 920)
        .commands {
            ReviewCommands(workspace: workspace, inbox: inbox, settings: settings)
        }

        Settings {
            SettingsView(settings: settings, account: account, watcher: watcher)
                .environment(settings)
        }
    }
}

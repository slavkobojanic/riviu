import SwiftUI

@main
struct RiviuApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var settings: AppSettings
    @State private var account: GitHubAccount
    @State private var inbox: PullRequestInbox
    @State private var workspace: ReviewWorkspace
    @State private var chats: ChatStore
    @State private var aiReviews: AIReviewStore
    @State private var watcher: ReviewRequestWatcher
    private let notifications = ReviewRequestNotifications()
    private let mainWindow = MainWindow()

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

        let mainWindow = mainWindow
        notifications.onOpen = { reference in
            mainWindow.show()
            workspace.open(reference)
        }
        watcher.start()
    }

    var body: some Scene {
        Window("Riviu", id: MainWindow.id) {
            ReviewWindow(workspace: workspace, inbox: inbox, account: account, chats: chats, aiReviews: aiReviews,
                         watcher: watcher, settings: settings)
                .remembersOpenWindow(in: mainWindow)
                .onAppear { appDelegate.settings = settings }
                .onDisappear { mainWindow.didClose(keepsRunningInMenuBar: settings.keepsRunningInMenuBar) }
        }
        .defaultSize(width: 1500, height: 920)
        .commands {
            ReviewCommands(workspace: workspace, watcher: watcher, settings: settings)
        }

        MenuBarExtra(isInserted: $settings.keepsRunningInMenuBar) {
            MenuBarPanel(watcher: watcher, account: account, aiReviews: aiReviews, workspace: workspace, mainWindow: mainWindow)
        } label: {
            MenuBarLabel(waitingCount: watcher.requests.count)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, account: account, watcher: watcher)
                .environment(settings)
        }
    }
}

/// The menu bar icon, with the number of pull requests waiting for your review.
private struct MenuBarLabel: View {
    let waitingCount: Int

    var body: some View {
        if waitingCount > 0 {
            Label("\(waitingCount)", image: "MenuBarIcon")
                .labelStyle(.titleAndIcon)
        } else {
            Label("Riviu", image: "MenuBarIcon")
                .labelStyle(.iconOnly)
        }
    }
}

import SwiftUI

@main
struct RiviuApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var settings: AppSettings
    @State private var account: GitHubAccount
    @State private var inbox: PullRequestInbox
    @State private var tabs: ReviewTabs
    @State private var chats: ChatStore
    @State private var aiReviews: AIReviewStore
    @State private var rules: ReviewRuleStore
    @State private var watcher: ReviewRequestWatcher
    private let notifications = ReviewRequestNotifications()
    private let updates = Updates()

    init() {
        let settings = AppSettings()
        let account = GitHubAccount()
        _settings = State(initialValue: settings)
        _account = State(initialValue: account)
        let inbox = PullRequestInbox(account: account)
        let rules = ReviewRuleStore()
        let aiReviews = AIReviewStore(settings: settings, account: account, rules: rules)
        let codeIndexes = CodeIndexStore(account: account)
        let tabs = ReviewTabs(settings: settings) {
            ReviewWorkspace(settings: settings, account: account, aiReviews: aiReviews, rules: rules, codeIndexes: codeIndexes)
        }
        let watcher = ReviewRequestWatcher(account: account, settings: settings, aiReviews: aiReviews, inbox: inbox,
                                           notifications: notifications)
        _inbox = State(initialValue: inbox)
        _aiReviews = State(initialValue: aiReviews)
        _rules = State(initialValue: rules)
        _tabs = State(initialValue: tabs)
        _watcher = State(initialValue: watcher)
        _chats = State(initialValue: ChatStore(makeProvider: { try AISetup.makeProvider(for: .chat, settings: settings) }))

        notifications.onOpen = { reference in
            tabs.open(reference)
        }
        watcher.start()
        #if DEBUG
        DebugLaunch.run(tabs: tabs, account: account, aiReviews: aiReviews, watcher: watcher)
        #endif
    }

    var body: some Scene {
        // New tabs and pull requests open as tabs in one window; ReviewTabs puts them in the same tab group.
        // File > New Window follows the system's "Prefer tabs" setting.
        WindowGroup("Riviu", id: ReviewTabs.windowID) {
            ReviewTab(tabs: tabs, inbox: inbox, account: account, chats: chats, aiReviews: aiReviews, watcher: watcher,
                      settings: settings)
                .onAppear { appDelegate.settings = settings }
        }
        .defaultSize(width: 1500, height: 920)
        .commands {
            // Show Toolbar, Customize Toolbar… and Show Sidebar in the View menu.
            UpdateCommands(updates: updates)
            ToolbarCommands()
            SidebarCommands()
            ReviewCommands(tabs: tabs, watcher: watcher, settings: settings)
        }

        MenuBarExtra(isInserted: $settings.keepsRunningInMenuBar) {
            MenuBarPanel(watcher: watcher, account: account, aiReviews: aiReviews, tabs: tabs)
        } label: {
            MenuBarLabel(waitingCount: watcher.requests.count)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, account: account, watcher: watcher, rules: rules)
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

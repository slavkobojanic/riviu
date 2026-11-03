import SwiftUI

@main
struct RiviuApp: App {
    @State private var settings: AppSettings
    @State private var account: GitHubAccount
    @State private var inbox: PullRequestInbox
    @State private var workspace: ReviewWorkspace
    @State private var chats: ChatStore

    init() {
        let settings = AppSettings()
        let account = GitHubAccount()
        _settings = State(initialValue: settings)
        _account = State(initialValue: account)
        _inbox = State(initialValue: PullRequestInbox(account: account))
        _workspace = State(initialValue: ReviewWorkspace(findings: DemoPullRequests.findings, settings: settings, account: account))
        _chats = State(initialValue: ChatStore(makeProvider: { try AISetup.makeProvider(for: .chat, settings: settings) }))
    }

    var body: some Scene {
        Window("Riviu", id: "review") {
            ReviewWindow(workspace: workspace, inbox: inbox, account: account, chats: chats, settings: settings)
        }
        .defaultSize(width: 1500, height: 920)
        .commands {
            ReviewCommands(workspace: workspace, inbox: inbox, settings: settings)
        }

        Settings {
            SettingsView(settings: settings, account: account)
                .environment(settings)
        }
    }
}

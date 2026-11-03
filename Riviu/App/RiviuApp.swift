import SwiftUI

@main
struct RiviuApp: App {
    @State private var settings: AppSettings
    @State private var workspace: ReviewWorkspace
    @State private var chats: ChatStore

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _workspace = State(initialValue: ReviewWorkspace(pullRequests: DemoPullRequests.all, findings: DemoPullRequests.findings, settings: settings))
        _chats = State(initialValue: ChatStore(makeProvider: { try AISetup.makeProvider(settings: settings) }))
    }

    var body: some Scene {
        Window("Riviu", id: "review") {
            ReviewWindow(workspace: workspace, chats: chats, settings: settings)
        }
        .defaultSize(width: 1500, height: 920)
        .commands {
            ReviewCommands(workspace: workspace, settings: settings)
        }

        Settings {
            SettingsView(settings: settings)
        }
    }
}

import RiviuDiff
import SwiftUI

/// Menu bar commands and their keyboard shortcuts.
struct ReviewCommands: Commands {
    let workspace: ReviewWorkspace
    let inbox: PullRequestInbox
    let settings: AppSettings

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Section {
                Button("Find…") { workspace.showFind() }
                    .keyboardShortcut("f")
                Button("Find Next") { workspace.findNext() }
                    .keyboardShortcut("g")
                Button("Find Previous") { workspace.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        CommandMenu("Review") {
            Button("Refresh Pull Requests") { inbox.refresh() }
                .keyboardShortcut("r")
            Divider()
            Button(workspace.isSelectedFileViewed ? "Mark as Not Viewed" : "Mark as Viewed") { workspace.toggleViewedForSelectedFile() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            Button("Next File") { workspace.selectAdjacentFile(offset: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous File") { workspace.selectAdjacentFile(offset: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Divider()
            Button(settings.diffLayout == .split ? "Show Unified Diff" : "Show Split Diff") {
                settings.diffLayout = settings.diffLayout == .split ? .unified : .split
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            Button(workspace.expandAll ? "Collapse Unchanged Lines" : "Expand All Lines") { workspace.expandAll.toggle() }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Divider()
            Button(settings.showsChatPanel ? "Hide AI Chat" : "Show AI Chat") { settings.showsChatPanel.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

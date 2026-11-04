import AppKit
import RiviuDiff
import RiviuGitHub
import SwiftUI

/// Menu bar commands and their keyboard shortcuts.
///
/// Shortcuts avoid the system's own: ⌥⌘D shows and hides the Dock, ⌃⌘D looks up a word, and ⇧⌘V is
/// Paste and Match Style in many apps.
struct ReviewCommands: Commands {
    let tabs: ReviewTabs
    let watcher: ReviewRequestWatcher
    let settings: AppSettings

    /// The tab in front.
    private var workspace: ReviewWorkspace { tabs.current }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") { tabs.openNewTab() }
                .keyboardShortcut("t")
        }

        // SwiftUI's Edit menu has no Find items of its own (those come with TextEditingCommands, which Riviu
        // doesn't add), so these are the only ones. A submenu, like other Mac apps.
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find…") { workspace.showFind() }
                    .keyboardShortcut("f")
                Button("Find Next") { workspace.findNext() }
                    .keyboardShortcut("g")
                Button("Find Previous") { workspace.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        // How the diff is drawn, at the top of the View menu.
        CommandGroup(before: .toolbar) {
            Button(settings.diffLayout == .split ? "Show Unified Diff" : "Show Split Diff") {
                settings.diffLayout = settings.diffLayout == .split ? .unified : .split
            }
            .keyboardShortcut("l", modifiers: [.command, .control])
            Button(workspace.expandAll ? "Collapse Unchanged Lines" : "Expand All Lines") { workspace.expandAll.toggle() }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Button(workspace.hidesCosmeticChanges ? "Show Cosmetic Changes" : "Show Logic Changes Only") {
                workspace.hidesCosmeticChanges.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
        }

        // The chat is the window's inspector, so it sits next to Show Sidebar.
        CommandGroup(after: .sidebar) {
            Button(settings.showsChatPanel ? "Hide AI Chat" : "Show AI Chat") { settings.showsChatPanel.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }

        CommandMenu("Review") {
            Button("Refresh Pull Requests") { watcher.refreshAll() }
                .keyboardShortcut("r")
            Button("Show Pull Requests") { workspace.showPullRequestList() }
                .disabled(workspace.sidebarPage == .pullRequests)
            Divider()
            Button("Back") { workspace.goBack() }
                .keyboardShortcut("[")
                .disabled(!workspace.canGoBack)
            Button("Forward") { workspace.goForward() }
                .keyboardShortcut("]")
                .disabled(!workspace.canGoForward)
            Divider()
            Button(workspace.isSelectedFileViewed ? "Mark as Not Viewed" : "Mark as Viewed") { workspace.toggleViewedForSelectedFile() }
                .keyboardShortcut("v", modifiers: [.command, .control])
                .disabled(workspace.selectedFile == nil || workspace.showsOverview)
            Divider()
            Button("Next File") { workspace.selectAdjacentFile(offset: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous File") { workspace.selectAdjacentFile(offset: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Next Conversation") { workspace.revealAdjacentThread(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(workspace.unresolvedThreads.isEmpty)
            Button("Previous Conversation") { workspace.revealAdjacentThread(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(workspace.unresolvedThreads.isEmpty)
            Divider()
            if workspace.isTouring {
                Button("End Guided Tour") { workspace.endTour() }
            } else {
                Button("Start Guided Tour") { workspace.startTour() }
                    .disabled(workspace.tour == nil)
            }
            Button("Next Tour Stop") { workspace.advanceTour(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!workspace.isTouring)
            Button("Previous Tour Stop") { workspace.advanceTour(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!workspace.isTouring)
            Divider()
            Button("Open on GitHub") {
                if let url = workspace.pullRequest?.webURL { NSWorkspace.shared.open(url) }
            }
            .disabled(workspace.pullRequest?.webURL == nil)
            // Opens the same sheet as the toolbar's Submit Review button.
            Button("Submit Review…") { workspace.reviewSheetVerdict = .comment }
                .disabled(!workspace.canSubmitReview)
        }
    }
}

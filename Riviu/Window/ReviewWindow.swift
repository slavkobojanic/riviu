import RiviuDiff
import SwiftUI

/// The main window: changed files on the left, the diff in the middle, AI chat on the right.
struct ReviewWindow: View {
    @Bindable var workspace: ReviewWorkspace
    let inbox: PullRequestInbox
    let account: GitHubAccount
    let chats: ChatStore
    let aiReviews: AIReviewStore
    let watcher: ReviewRequestWatcher
    @Bindable var settings: AppSettings
    @State private var showsReviewSheet = false

    var body: some View {
        NavigationSplitView {
            Sidebar(workspace: workspace, inbox: inbox, account: account, aiReviews: aiReviews, watcher: watcher)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
        } detail: {
            ReviewDetail(workspace: workspace, aiReviews: aiReviews, display: display, settings: settings, chats: chats)
                .inspector(isPresented: $settings.showsChatPanel) {
                    ChatPanel(chats: chats, workspace: workspace)
                        .inspectorColumnWidth(min: 300, ideal: 380, max: 600)
                }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .sheet(isPresented: $showsReviewSheet) {
            ReviewSubmissionSheet(workspace: workspace)
        }
        .environment(settings)
        .preferredColorScheme(settings.appearance.colorScheme)
        .onChange(of: settings.diffLayout) { workspace.rebuildRows() }
        .onChange(of: settings.contextLines) { workspace.rebuildRows() }
        .onChange(of: settings.highlightsWordChanges) { workspace.rebuildRows() }
        .onChange(of: workspace.findings.map(\.id)) { workspace.rebuildRows() }
        .onChange(of: workspace.pullRequest?.reference, initial: true) { _, reference in
            if let reference { chats.showLatestChat(about: reference) }
        }
    }

    private var display: DiffDisplay {
        DiffDisplay(rowsVersion: workspace.rowsVersion, syntaxVersion: workspace.syntaxVersion, layout: settings.diffLayout,
                    themeFamily: settings.themeFamily, font: settings.editorFont, lineSpacing: settings.lineSpacing,
                    findQuery: workspace.isFindVisible ? workspace.findQuery : "", findStep: workspace.findStep,
                    lineToReveal: workspace.lineToReveal)
    }

    private var isShowingFile: Bool {
        workspace.selectedFile != nil && !workspace.showsOverview
    }

    private var title: String {
        guard let pullRequest = workspace.pullRequest else { return "Riviu" }
        if workspace.showsOverview { return "Overview" }
        return workspace.selectedFile?.fileName ?? pullRequest.title
    }

    private var subtitle: String {
        guard let pullRequest = workspace.pullRequest else { return "" }
        guard let file = workspace.selectedFile, !workspace.showsOverview else { return pullRequest.reference.id }
        let location = file.directory.isEmpty ? "" : file.directory + " · "
        return "\(location)+\(file.additions) −\(file.deletions)"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Layout", selection: $settings.diffLayout) {
                Label("Unified", systemImage: "rectangle").tag(DiffLayout.unified)
                Label("Split", systemImage: "rectangle.split.2x1").tag(DiffLayout.split)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Unified or split diff (⌥⌘D)")
        }
        ToolbarItemGroup {
            Toggle(isOn: Binding(get: { workspace.isSelectedFileViewed }, set: { _ in workspace.toggleViewedForSelectedFile() })) {
                Label("Viewed", systemImage: workspace.isSelectedFileViewed ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .help("Mark this file as viewed (⇧⌘V)")
            .disabled(!isShowingFile)
            Toggle(isOn: $workspace.expandAll) {
                Label("Expand All", systemImage: "arrow.up.and.down")
            }
            .help("Show every unchanged line (⌥⌘E)")
            .disabled(!isShowingFile)
            Toggle(isOn: $workspace.hidesCosmeticChanges) {
                Label("Logic Changes Only", systemImage: "line.3.horizontal.decrease")
            }
            .help("Hide hunks that only move, rename or reformat code (⌥⌘L)")
            .disabled(!isShowingFile)
            Button("Find", systemImage: "magnifyingglass") { workspace.showFind() }
                .help("Find in file (⌘F)")
                .disabled(!isShowingFile)
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            if let url = workspace.pullRequest?.webURL {
                Link(destination: url) {
                    Label("Open on GitHub", systemImage: "safari")
                }
                .help("Open this pull request on GitHub")
            }
            Button("Submit Review", systemImage: "paperplane") { showsReviewSheet = true }
                .disabled(!workspace.canSubmitReview)
                .help(workspace.canSubmitReview ? "Post your comments and verdict to GitHub" : "Open a GitHub pull request to submit a review")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Toggle(isOn: $settings.showsChatPanel) {
                Label("AI Chat", systemImage: "sidebar.trailing")
            }
            .help("Show or hide AI chat (⌥⌘I)")
        }
    }
}

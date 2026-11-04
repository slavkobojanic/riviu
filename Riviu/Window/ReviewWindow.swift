import RiviuDiff
import RiviuGitHub
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
    @Environment(\.openURL) private var openURL

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
        // An id for the toolbar and each item, so View > Customize Toolbar… can rearrange them.
        .toolbar(id: "review") { toolbar }
        .sheet(isPresented: showsReviewSheet) {
            ReviewSubmissionSheet(workspace: workspace, initialEvent: workspace.reviewSheetVerdict ?? .comment)
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

    private var showsReviewSheet: Binding<Bool> {
        Binding(get: { workspace.reviewSheetVerdict != nil }, set: { if !$0 { workspace.reviewSheetVerdict = nil } })
    }

    private var isShowingFile: Bool {
        workspace.selectedFile != nil && !workspace.showsOverview
    }

    /// Also the tab's name, so it's the pull request rather than the file.
    private var title: String {
        if let pullRequest = workspace.pullRequest { return pullRequest.title }
        if let reference = workspace.loadingReference { return reference.id }
        return "Pull Requests"
    }

    private var subtitle: String {
        guard let pullRequest = workspace.pullRequest else { return "" }
        guard let file = workspace.selectedFile, !workspace.showsOverview else { return "\(pullRequest.reference.id)  Overview" }
        return "\(file.path)  +\(file.additions) −\(file.deletions)"
    }

    @ToolbarContentBuilder
    private var toolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "layout", placement: .principal) {
            Picker("Layout", selection: $settings.diffLayout) {
                Label("Unified", systemImage: "rectangle").tag(DiffLayout.unified)
                Label("Split", systemImage: "rectangle.split.2x1").tag(DiffLayout.split)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Unified or split diff (⌃⌘L)")
            .disabled(!isShowingFile)
        }
        ToolbarItem(id: "viewed") {
            Toggle(isOn: Binding(get: { workspace.isSelectedFileViewed }, set: { _ in workspace.toggleViewedForSelectedFile() })) {
                Label("Viewed", systemImage: workspace.isSelectedFileViewed ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .help("Mark this file as viewed (⌃⌘V)")
            .disabled(!isShowingFile)
        }
        ToolbarItem(id: "expandAll") {
            Toggle(isOn: $workspace.expandAll) {
                Label("Expand All", systemImage: "arrow.up.and.down")
            }
            .help("Show every unchanged line (⌥⌘E)")
            .disabled(!isShowingFile)
        }
        ToolbarItem(id: "logicChangesOnly") {
            Toggle(isOn: $workspace.hidesCosmeticChanges) {
                Label("Logic Changes Only", systemImage: "line.3.horizontal.decrease")
            }
            .help("Hide hunks that only move, rename or reformat code (⌥⌘L)")
            .disabled(!isShowingFile)
        }
        ToolbarItem(id: "find") {
            Button("Find", systemImage: "magnifyingglass") { workspace.showFind() }
                .help("Find in file (⌘F)")
                .disabled(!isShowingFile)
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(id: "openOnGitHub") {
            // A Button rather than a Link, so it's drawn like the other toolbar buttons. It stays in the toolbar
            // with nothing open, so customizing the toolbar always shows it.
            Button("Open on GitHub", systemImage: "safari") {
                if let url = workspace.pullRequest?.webURL { openURL(url) }
            }
            .help("Open this pull request on GitHub")
            .disabled(workspace.pullRequest?.webURL == nil)
        }
        ToolbarItem(id: "submitReview") {
            Button("Submit Review", systemImage: "paperplane") { workspace.reviewSheetVerdict = .comment }
                .disabled(!workspace.canSubmitReview)
                .help(workspace.canSubmitReview ? "Post your comments and verdict to GitHub" : "Open a GitHub pull request to submit a review")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(id: "aiChat") {
            Toggle(isOn: $settings.showsChatPanel) {
                Label("AI Chat", systemImage: "sidebar.trailing")
            }
            .help("Show or hide AI chat (⌥⌘I)")
        }
    }
}

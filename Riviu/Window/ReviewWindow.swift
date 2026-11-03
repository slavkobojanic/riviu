import RiviuDiff
import SwiftUI

/// The main window: changed files on the left, the diff in the middle, AI chat on the right.
struct ReviewWindow: View {
    @Bindable var workspace: ReviewWorkspace
    let inbox: PullRequestInbox
    let account: GitHubAccount
    let chats: ChatStore
    @Bindable var settings: AppSettings
    @State private var showsReviewSheet = false

    var body: some View {
        NavigationSplitView {
            Sidebar(workspace: workspace, inbox: inbox, account: account)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
        } detail: {
            ReviewDetail(workspace: workspace, display: display, settings: settings, chats: chats)
                .inspector(isPresented: $settings.showsChatPanel) {
                    ChatPanel(chats: chats, workspace: workspace)
                        .inspectorColumnWidth(min: 300, ideal: 380, max: 600)
                }
        }
        .navigationTitle(workspace.selectedFile?.fileName ?? workspace.pullRequest?.title ?? "Riviu")
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
        .onChange(of: workspace.pullRequest?.reference, initial: true) { _, reference in
            if let reference { chats.showLatestChat(about: reference) }
        }
    }

    private var display: DiffDisplay {
        DiffDisplay(rowsVersion: workspace.rowsVersion, syntaxVersion: workspace.syntaxVersion, layout: settings.diffLayout,
                    themeFamily: settings.themeFamily, font: settings.editorFont, lineSpacing: settings.lineSpacing,
                    findQuery: workspace.isFindVisible ? workspace.findQuery : "", findStep: workspace.findStep)
    }

    private var subtitle: String {
        guard let pullRequest = workspace.pullRequest else { return "" }
        guard let file = workspace.selectedFile else { return pullRequest.reference.id }
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
            Toggle(isOn: $workspace.expandAll) {
                Label("Expand All", systemImage: "arrow.up.and.down")
            }
            .help("Show every unchanged line (⌥⌘E)")
            Button("Find", systemImage: "magnifyingglass") { workspace.showFind() }
                .help("Find in file (⌘F)")
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

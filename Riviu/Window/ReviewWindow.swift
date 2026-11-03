import RiviuDiff
import SwiftUI

/// The main window: changed files on the left, the diff in the middle, AI chat on the right.
struct ReviewWindow: View {
    @Bindable var workspace: ReviewWorkspace
    let chats: ChatStore
    @Bindable var settings: AppSettings

    var body: some View {
        NavigationSplitView {
            FileSidebar(workspace: workspace)
                .id(workspace.pullRequest.number) // fresh folder expansion state for each pull request
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 440)
        } detail: {
            diff
                .inspector(isPresented: $settings.showsChatPanel) {
                    ChatPanel(chats: chats, workspace: workspace)
                        .inspectorColumnWidth(min: 300, ideal: 380, max: 600)
                }
        }
        .navigationTitle(workspace.selectedFile?.fileName ?? "Riviu")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .preferredColorScheme(settings.appearance.colorScheme)
        .onChange(of: settings.diffLayout) { workspace.rebuildRows() }
        .onChange(of: settings.contextLines) { workspace.rebuildRows() }
        .onChange(of: settings.highlightsWordChanges) { workspace.rebuildRows() }
        .onChange(of: workspace.pullRequest.number, initial: true) { _, number in
            chats.showLatestChat(forPullRequest: number)
        }
    }

    private var diff: some View {
        ZStack(alignment: .topTrailing) {
            DiffView(display: display, workspace: workspace, settings: settings, chats: chats)
                .ignoresSafeArea(.container, edges: .top)
            if workspace.isFindVisible {
                FindBar(workspace: workspace)
                    .padding(14)
            }
        }
    }

    private var display: DiffDisplay {
        DiffDisplay(rowsVersion: workspace.rowsVersion, syntaxVersion: workspace.syntaxVersion, layout: settings.diffLayout,
                    themeFamily: settings.themeFamily, font: settings.editorFont, lineSpacing: settings.lineSpacing,
                    findQuery: workspace.isFindVisible ? workspace.findQuery : "", findStep: workspace.findStep)
    }

    private var subtitle: String {
        guard let file = workspace.selectedFile else { return "" }
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
        ToolbarItem {
            Toggle(isOn: $settings.showsChatPanel) {
                Label("AI Chat", systemImage: "sidebar.trailing")
            }
            .help("Show or hide AI chat (⌥⌘I)")
        }
    }
}

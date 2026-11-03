import SwiftUI

/// The middle of the window: the diff of the selected file, or what's happening instead.
struct ReviewDetail: View {
    let workspace: ReviewWorkspace
    let display: DiffDisplay
    let settings: AppSettings
    let chats: ChatStore

    var body: some View {
        if let message = workspace.openErrorMessage {
            ContentUnavailableView {
                Label("Couldn't Open Pull Request", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { workspace.retryOpening() }
            }
        } else if let reference = workspace.loadingReference {
            ProgressView("Loading \(reference.id)…")
        } else if workspace.pullRequest == nil {
            ContentUnavailableView("No Pull Request Open", systemImage: "arrow.triangle.pull",
                                   description: Text("Choose a pull request in the sidebar."))
        } else {
            fileContent
        }
    }

    @ViewBuilder
    private var fileContent: some View {
        switch workspace.selectedFileContent {
        case .loaded:
            ZStack(alignment: .topTrailing) {
                DiffView(display: display, workspace: workspace, settings: settings, chats: chats)
                    .ignoresSafeArea(.container, edges: .top)
                if workspace.isFindVisible {
                    FindBar(workspace: workspace)
                        .padding(14)
                }
            }
        case .binary:
            ContentUnavailableView("Binary File", systemImage: "doc.zipper", description: Text("Binary files can't be shown as a diff."))
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't Load File", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { workspace.retryLoadingSelectedFile() }
            }
        case .loading:
            ProgressView("Loading \(workspace.selectedFile?.fileName ?? "file")…")
        case nil:
            ContentUnavailableView("No File Selected", systemImage: "doc", description: Text("Choose a file in the sidebar."))
        }
    }
}

import RiviuDiff
import RiviuSyntax
import SwiftUI

/// The open pull request's changed files as a folder tree.
struct FileSidebar: View {
    let workspace: ReviewWorkspace
    let onBack: () -> Void
    @State private var expandedFolders: Set<String>

    init(workspace: ReviewWorkspace, onBack: @escaping () -> Void) {
        self.workspace = workspace
        self.onBack = onBack
        let paths = workspace.pullRequest?.files.map(\.path) ?? []
        _expandedFolders = State(initialValue: Set(FileTreeNode.tree(for: paths).flatMap(\.folderIDs)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Pull Requests", systemImage: "chevron.left", action: onBack)
                .buttonStyle(.borderless)
                .padding(.horizontal, 14)
                .padding(.top, 6)
            if let pullRequest = workspace.pullRequest, workspace.loadingReference == nil {
                PullRequestHeader(pullRequest: pullRequest)
                List(selection: selection) {
                    Section {
                        ForEach(FileTreeNode.tree(for: pullRequest.files.map(\.path))) { node in
                            FileTreeRow(node: node, workspace: workspace, expandedFolders: $expandedFolders)
                        }
                    } header: {
                        ChangedFilesHeader(workspace: workspace, pullRequest: pullRequest)
                    }
                }
                .listStyle(.sidebar)
            } else if workspace.openErrorMessage == nil {
                ProgressView("Loading pull request…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
    }

    /// Clicking a folder doesn't change the selected file.
    private var selection: Binding<String?> {
        Binding(get: { workspace.selectedFilePath }, set: { workspace.selectFile(at: $0) })
    }
}

private struct ChangedFilesHeader: View {
    let workspace: ReviewWorkspace
    let pullRequest: PullRequest

    var body: some View {
        HStack(spacing: 6) {
            Text("\(workspace.viewedFileCount) of \(pullRequest.files.count) viewed")
            Spacer()
            Text("+\(pullRequest.additions)")
                .foregroundStyle(.green)
            Text("−\(pullRequest.deletions)")
                .foregroundStyle(.red)
        }
        .monospacedDigit()
        .padding(.trailing, 10)
    }
}

private struct FileTreeRow: View {
    let node: FileTreeNode
    let workspace: ReviewWorkspace
    @Binding var expandedFolders: Set<String>

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(children) { child in
                    FileTreeRow(node: child, workspace: workspace, expandedFolders: $expandedFolders)
                }
            } label: {
                Label(node.name, systemImage: "folder")
            }
        } else if let file = workspace.pullRequest?.file(at: node.id) {
            FileRow(file: file, workspace: workspace)
                .tag(file.path)
        }
    }

    private var isExpanded: Binding<Bool> {
        Binding(get: { expandedFolders.contains(node.id) },
                set: { isOpen in
                    if isOpen {
                        expandedFolders.insert(node.id)
                    } else {
                        expandedFolders.remove(node.id)
                    }
                })
    }
}

private struct FileRow: View {
    let file: ChangedFile
    let workspace: ReviewWorkspace

    var body: some View {
        HStack(spacing: 6) {
            Label(file.fileName, systemImage: icon)
                .lineLimit(1)
            Spacer(minLength: 4)
            let commentCount = workspace.commentCount(forFileAt: file.path)
            if commentCount > 0 {
                Label("\(commentCount)", systemImage: "text.bubble")
                    .font(.caption)
                    .help("\(commentCount) pending comment(s)")
            }
            if !workspace.findings(inFileAt: file.path).isEmpty {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .help("AI findings")
            }
            if workspace.isViewed(file.path) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Viewed")
            } else {
                Text(statusLetter)
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(statusColor)
                    .help(statusHelp)
            }
        }
        .padding(.trailing, 4)
    }

    private var icon: String {
        switch SyntaxLanguage.detect(path: file.path) {
        case .swift: "swift"
        case .markdown: "doc.richtext"
        case .json: "curlybraces"
        default: "doc.text"
        }
    }

    private var statusLetter: String {
        switch file.status {
        case .added: "A"
        case .deleted: "D"
        case .modified: "M"
        case .renamed: "R"
        }
    }

    private var statusHelp: String {
        switch file.status {
        case .added: "Added"
        case .deleted: "Deleted"
        case .modified: "Modified"
        case .renamed: "Renamed from \(file.previousPath ?? "another path")"
        }
    }

    private var statusColor: Color {
        switch file.status {
        case .added: .green
        case .deleted: .red
        case .modified: .orange
        case .renamed: .blue
        }
    }
}

private struct PullRequestHeader: View {
    let pullRequest: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(pullRequest.reference.isDemo ? "Demo" : pullRequest.reference.repository) #\(pullRequest.number) · \(pullRequest.author)")
                .font(.caption.weight(.semibold))
            Text(pullRequest.title)
                .font(.headline)
                .lineLimit(3)
            Label("\(pullRequest.headBranch) → \(pullRequest.baseBranch)", systemImage: "arrow.triangle.branch")
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

import RiviuDiff
import RiviuSyntax
import SwiftUI

/// The pull request picker and its changed files as a folder tree.
struct FileSidebar: View {
    let workspace: ReviewWorkspace
    @State private var expandedFolders: Set<String>

    init(workspace: ReviewWorkspace) {
        self.workspace = workspace
        let tree = FileTreeNode.tree(for: workspace.pullRequest.files.map(\.path))
        _expandedFolders = State(initialValue: Set(tree.flatMap(\.folderIDs)))
    }

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(tree) { node in
                    FileTreeRow(node: node, workspace: workspace, expandedFolders: $expandedFolders)
                }
            } header: {
                ChangedFilesHeader(workspace: workspace)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            PullRequestPicker(workspace: workspace)
        }
    }

    private var tree: [FileTreeNode] {
        FileTreeNode.tree(for: workspace.pullRequest.files.map(\.path))
    }

    /// Clicking a folder doesn't change the selected file.
    private var selection: Binding<String?> {
        Binding(get: { workspace.selectedFilePath }, set: { workspace.selectFile(at: $0) })
    }
}

private struct ChangedFilesHeader: View {
    let workspace: ReviewWorkspace

    var body: some View {
        let pullRequest = workspace.pullRequest
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
        } else if let file = workspace.pullRequest.file(at: node.id) {
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
    let file: FileDiff
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
            if !workspace.findings(in: file).isEmpty {
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
        }
    }

    private var statusHelp: String {
        switch file.status {
        case .added: "Added"
        case .deleted: "Deleted"
        case .modified: "Modified"
        }
    }

    private var statusColor: Color {
        switch file.status {
        case .added: .green
        case .deleted: .red
        case .modified: .orange
        }
    }
}

private struct PullRequestPicker: View {
    let workspace: ReviewWorkspace

    var body: some View {
        let current = workspace.pullRequest
        Menu {
            ForEach(workspace.pullRequests) { pullRequest in
                Button("#\(pullRequest.number) \(pullRequest.title)") {
                    workspace.selectPullRequest(number: pullRequest.number)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(current.number) · \(current.author)")
                    .font(.caption.weight(.semibold))
                Text(current.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Label(current.branch, systemImage: "arrow.triangle.branch")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

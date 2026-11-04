import RiviuDiff
import RiviuSyntax
import SwiftUI

/// The open pull request's changed files as a folder tree.
struct FileSidebar: View {
    let workspace: ReviewWorkspace
    let aiReviews: AIReviewStore
    let onBack: () -> Void
    @State private var expandedFolders: Set<String>

    init(workspace: ReviewWorkspace, aiReviews: AIReviewStore, onBack: @escaping () -> Void) {
        self.workspace = workspace
        self.aiReviews = aiReviews
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
                PullRequestHeader(pullRequest: pullRequest, workspace: workspace, aiReviews: aiReviews)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                if let sinceLastReview = workspace.sinceLastReview {
                    ChangesPicker(workspace: workspace, sinceLastReview: sinceLastReview)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                }
                List(selection: selection) {
                    Section {
                        ForEach(FileTreeNode.tree(for: workspace.visibleFiles.map(\.path))) { node in
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

    /// No file is highlighted while the overview is shown. Clicking a folder doesn't change the selected file.
    private var selection: Binding<String?> {
        Binding(get: { workspace.showsOverview ? nil : workspace.selectedFilePath },
                set: { workspace.selectFile(at: $0) })
    }
}

/// All changes, or only what changed since your last review.
private struct ChangesPicker: View {
    let workspace: ReviewWorkspace
    let sinceLastReview: SinceLastReview

    var body: some View {
        Picker("Show", selection: Binding(get: { workspace.showsChangesSinceLastReview },
                                          set: { workspace.setShowsChangesSinceLastReview($0) })) {
            Text("All Changes").tag(false)
            Text("Since My Review (\(sinceLastReview.files.count))").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Show only the files that changed since your last review, \(sinceLastReview.reviewedAt.formatted(.relative(presentation: .named)))")
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
        } else if let file = workspace.visibleFile(at: node.id) {
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
            let ciCount = workspace.annotationCount(forFileAt: file.path)
            if ciCount > 0 {
                Label("\(ciCount)", systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help("\(ciCount) CI message(s)")
            }
            let threadCount = workspace.unresolvedThreadCount(forFileAt: file.path)
            if threadCount > 0 {
                Label("\(threadCount)", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .help("\(threadCount) unresolved conversation(s)")
            }
            if !workspace.findings(inFileAt: file.path).isEmpty {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .help("AI findings")
            }
            if workspace.isChangedSinceViewed(file.path) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .help("Changed since you viewed it")
            } else if workspace.isViewed(file.path) {
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

/// The pull request's title and AI status. Clicking it shows the overview.
private struct PullRequestHeader: View {
    let pullRequest: PullRequest
    let workspace: ReviewWorkspace
    let aiReviews: AIReviewStore
    @State private var isHovered = false

    var body: some View {
        Button { workspace.showOverview() } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(pullRequest.reference.isDemo ? "Demo" : pullRequest.reference.repository) #\(String(pullRequest.number)) · \(pullRequest.author)")
                    .font(.caption.weight(.semibold))
                Text(pullRequest.title)
                    .font(.headline)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Label("\(pullRequest.headBranch) → \(pullRequest.baseBranch)", systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    AIReviewStatusLabel(reference: pullRequest.reference, aiReviews: aiReviews, placeholder: "Overview & AI summary")
                    ChecksSummaryLabel(checkRuns: workspace.checkRuns)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(background, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Show the pull request overview and AI summary")
    }

    private var background: AnyShapeStyle {
        if workspace.showsOverview { return AnyShapeStyle(Color.accentColor.opacity(0.2)) }
        if isHovered { return AnyShapeStyle(.fill.tertiary) }
        return AnyShapeStyle(.clear)
    }
}

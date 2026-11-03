import Foundation
import Observation
import RiviuDiff
import RiviuSyntax

/// What can appear between diff lines.
enum InlineItem {
    case finding(ReviewFinding)
    case comment(ReviewComment)
}

/// Asks the diff view to move to the next or previous find match. `count` changes on every request.
struct FindStep: Equatable {
    var count = 0
    var forward = true
}

/// Which match is selected (0-based, or -1) out of how many, as reported by the diff view.
struct FindStatus: Equatable {
    var current = -1
    var total = 0
}

/// The review the user is looking at: the selected pull request and file, the rows the diff view draws,
/// and the user's comments, viewed files and find-in-file state.
@Observable
final class ReviewWorkspace {
    let pullRequests: [PullRequest]
    private(set) var pullRequest: PullRequest

    var selectedFilePath: String? {
        didSet {
            guard selectedFilePath != oldValue else { return }
            expandedSegments = []
            rebuildRows()
            loadSyntax(forFileAt: selectedFilePath)
        }
    }

    var expandAll = false {
        didSet { rebuildRows() }
    }

    /// The rows for the selected file. `rowsVersion` changes whenever they are rebuilt.
    private(set) var rows: [DiffRow] = []
    private(set) var rowsVersion = 0
    /// Changes when syntax highlighting for the selected file finishes loading.
    private(set) var syntaxVersion = 0

    private(set) var findings: [ReviewFinding]
    private(set) var comments: [ReviewComment] = []
    private(set) var viewedFileKeys: Set<String> = []

    var isFindVisible = false
    var findQuery = "" {
        didSet {
            if findQuery != oldValue { rebuildRows() }
        }
    }
    private(set) var findStep = FindStep()
    var findStatus = FindStatus()

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var expandedSegments: Set<Int> = []
    @ObservationIgnored private var syntaxByPath: [String: (base: SyntaxDocument, head: SyntaxDocument)] = [:]
    @ObservationIgnored private var syntaxBeingLoaded: Set<String> = []

    init(pullRequests: [PullRequest], findings: [ReviewFinding], settings: AppSettings) {
        self.pullRequests = pullRequests
        self.findings = findings
        self.settings = settings
        pullRequest = pullRequests[0]
        selectedFilePath = pullRequest.files.first?.path
        rebuildRows()
        loadSyntax(forFileAt: selectedFilePath)
    }

    var selectedFile: FileDiff? {
        selectedFilePath.flatMap { pullRequest.file(at: $0) }
    }

    // MARK: - Navigation

    func selectPullRequest(number: Int) {
        guard number != pullRequest.number, let match = pullRequests.first(where: { $0.number == number }) else { return }
        pullRequest = match
        selectedFilePath = match.files.first?.path
    }

    /// Selects a file only if it's in the current pull request (folders in the sidebar are ignored).
    func selectFile(at path: String?) {
        guard let path, pullRequest.file(at: path) != nil else { return }
        selectedFilePath = path
    }

    func selectAdjacentFile(offset: Int) {
        let paths = pullRequest.files.map(\.path)
        guard let current = selectedFilePath, let index = paths.firstIndex(of: current) else { return }
        let next = index + offset
        if paths.indices.contains(next) {
            selectedFilePath = paths[next]
        }
    }

    // MARK: - Rows

    func rebuildRows() {
        guard let file = selectedFile else {
            rows = []
            rowsVersion += 1
            return
        }
        var options = DiffRowOptions()
        options.layout = settings.diffLayout
        options.contextLines = settings.contextLines
        options.highlightsWordChanges = settings.highlightsWordChanges
        options.expandAll = expandAll
        options.expandedSegments = expandedSegments.union(segmentsWithFindMatches(in: file))
        rows = DiffRowBuilder.rows(for: file, options: options, attachments: attachments(for: file))
        rowsVersion += 1
    }

    func expandSegment(_ index: Int) {
        expandedSegments.insert(index)
        rebuildRows()
    }

    private func attachments(for file: FileDiff) -> [Attachment] {
        let findingAttachments = findings(in: file).map {
            Attachment(id: Self.attachmentID(forFinding: $0.id), side: $0.side, lineIndex: $0.lineIndex)
        }
        let commentAttachments = comments(in: file).map {
            Attachment(id: Self.attachmentID(forComment: $0.id), side: $0.side, lineIndex: $0.lines.upperBound)
        }
        return findingAttachments + commentAttachments
    }

    private static func attachmentID(forFinding id: String) -> AttachmentID { AttachmentID("finding:" + id) }
    private static func attachmentID(forComment id: UUID) -> AttachmentID { AttachmentID("comment:" + id.uuidString) }

    func inlineItem(for id: AttachmentID) -> InlineItem? {
        if let finding = findings.first(where: { Self.attachmentID(forFinding: $0.id) == id }) {
            return .finding(finding)
        }
        if let comment = comments.first(where: { Self.attachmentID(forComment: $0.id) == id }) {
            return .comment(comment)
        }
        return nil
    }

    // MARK: - Syntax highlighting

    func syntax(forFileAt path: String?) -> (base: SyntaxDocument, head: SyntaxDocument)? {
        path.flatMap { syntaxByPath[$0] }
    }

    private func loadSyntax(forFileAt path: String?) {
        guard let path, let file = pullRequest.file(at: path), syntaxByPath[path] == nil, !syntaxBeingLoaded.contains(path) else { return }
        syntaxBeingLoaded.insert(path)
        let language = SyntaxLanguage.detect(path: path)
        Task {
            async let base = SyntaxDocument.parse(lines: file.baseLines, language: language)
            async let head = SyntaxDocument.parse(lines: file.headLines, language: language)
            syntaxByPath[path] = (await base, await head)
            syntaxBeingLoaded.remove(path)
            if path == selectedFilePath {
                syntaxVersion += 1
            }
        }
    }

    // MARK: - Viewed files

    private func viewedKey(for path: String) -> String { "\(pullRequest.number):\(path)" }

    func isViewed(_ path: String) -> Bool {
        viewedFileKeys.contains(viewedKey(for: path))
    }

    var isSelectedFileViewed: Bool {
        selectedFilePath.map(isViewed) ?? false
    }

    var viewedFileCount: Int {
        pullRequest.files.filter { isViewed($0.path) }.count
    }

    func toggleViewedForSelectedFile() {
        guard let path = selectedFilePath else { return }
        let key = viewedKey(for: path)
        if viewedFileKeys.contains(key) {
            viewedFileKeys.remove(key)
        } else {
            viewedFileKeys.insert(key)
        }
    }

    // MARK: - Find in file

    func showFind() {
        isFindVisible = true
    }

    func hideFind() {
        isFindVisible = false
        findQuery = ""
    }

    func findNext() {
        showFind()
        findStep = FindStep(count: findStep.count + 1, forward: true)
    }

    func findPrevious() {
        showFind()
        findStep = FindStep(count: findStep.count + 1, forward: false)
    }

    /// Collapsed segments that contain a match are expanded so every match can be shown.
    private func segmentsWithFindMatches(in file: FileDiff) -> Set<Int> {
        guard !findQuery.isEmpty else { return [] }
        var result = Set<Int>()
        for (index, segment) in file.segments.enumerated() {
            guard case let .unchanged(_, head) = segment else { continue }
            if head.contains(where: { file.headLines[$0].localizedCaseInsensitiveContains(findQuery) }) {
                result.insert(index)
            }
        }
        return result
    }

    // MARK: - Findings

    func findings(in file: FileDiff) -> [ReviewFinding] {
        findings.filter { $0.filePath == file.path }
    }

    func dismissFinding(_ finding: ReviewFinding) {
        findings.removeAll { $0.id == finding.id }
        rebuildRows()
    }

    func turnFindingIntoComment(_ finding: ReviewFinding) {
        guard let file = pullRequest.file(at: finding.filePath) else { return }
        let code = file.lines(on: finding.side)[finding.lineIndex]
        dismissFinding(finding)
        startComment(on: CodeTarget(filePath: file.path, side: finding.side, lines: finding.lineIndex...finding.lineIndex, code: code),
                     body: "**\(finding.title)**\n\n\(finding.body)")
    }

    // MARK: - Comments

    func comments(in file: FileDiff) -> [ReviewComment] {
        comments.filter { $0.pullRequestNumber == pullRequest.number && $0.filePath == file.path }
    }

    func commentCount(forFileAt path: String) -> Int {
        comments.filter { $0.pullRequestNumber == pullRequest.number && $0.filePath == path && !$0.isNew }.count
    }

    func startComment(on target: CodeTarget, body: String = "") {
        let comment = ReviewComment(id: UUID(), pullRequestNumber: pullRequest.number, filePath: target.filePath,
                                    side: target.side, lines: target.lines, code: target.code,
                                    body: body, isEditing: true, isNew: true)
        comments.append(comment)
        rebuildRows()
    }

    func saveComment(_ id: UUID, body: String) {
        updateComment(id) { comment in
            comment.body = body
            comment.isEditing = false
            comment.isNew = false
        }
    }

    func editComment(_ id: UUID) {
        updateComment(id) { $0.isEditing = true }
    }

    func cancelEditing(_ id: UUID) {
        guard let comment = comments.first(where: { $0.id == id }) else { return }
        if comment.isNew {
            deleteComment(id)
        } else {
            updateComment(id) { $0.isEditing = false }
        }
    }

    func deleteComment(_ id: UUID) {
        comments.removeAll { $0.id == id }
        rebuildRows()
    }

    private func updateComment(_ id: UUID, _ change: (inout ReviewComment) -> Void) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        change(&comments[index])
    }
}

import Foundation
import Observation
import RiviuDiff
import RiviuGitHub
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

/// The review the user is looking at: the open pull request and file, the rows the diff view draws,
/// and the user's comments, viewed files and find-in-file state.
@Observable
final class ReviewWorkspace {
    /// nil until a pull request is opened.
    private(set) var pullRequest: PullRequest?
    /// The pull request being opened, while it loads.
    private(set) var loadingReference: PullRequestReference?
    private(set) var openErrorMessage: String?

    var selectedFilePath: String? {
        didSet {
            guard selectedFilePath != oldValue else { return }
            expandedSegments = []
            rebuildRows()
            loadContent(ofFileAt: selectedFilePath)
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
    /// Loaded (or loading) contents of the open pull request's files, by path.
    private(set) var fileContents: [String: FileContent] = [:]

    private(set) var findings: [ReviewFinding]
    private(set) var comments: [ReviewComment] = []
    private(set) var viewedFileKeys: Set<String> = []
    private(set) var isSubmittingReview = false

    var isFindVisible = false
    var findQuery = "" {
        didSet {
            if findQuery != oldValue { rebuildRows() }
        }
    }
    private(set) var findStep = FindStep()
    var findStatus = FindStatus()

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let account: GitHubAccount
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var expandedSegments: Set<Int> = []
    @ObservationIgnored private var syntaxByPath: [String: (base: SyntaxDocument, head: SyntaxDocument)] = [:]

    init(findings: [ReviewFinding], settings: AppSettings, account: GitHubAccount) {
        self.findings = findings
        self.settings = settings
        self.account = account
    }

    var selectedFile: ChangedFile? {
        selectedFilePath.flatMap { pullRequest?.file(at: $0) }
    }

    var selectedFileContent: FileContent? {
        selectedFilePath.flatMap { fileContents[$0] }
    }

    var selectedFileDiff: FileDiff? {
        if case let .loaded(diff) = selectedFileContent { return diff }
        return nil
    }

    // MARK: - Opening pull requests

    func open(_ reference: PullRequestReference) {
        guard reference != pullRequest?.reference, reference != loadingReference else { return }
        openTask?.cancel()
        loadingReference = reference
        openErrorMessage = nil
        let loader = account.loader
        openTask = Task {
            do {
                let pullRequest = try await loader.pullRequest(reference)
                guard !Task.isCancelled else { return }
                show(pullRequest)
            } catch is CancellationError {
                return
            } catch {
                openErrorMessage = error.localizedDescription
            }
            loadingReference = nil
        }
    }

    func retryOpening() {
        guard let reference = loadingReference ?? pullRequest?.reference else { return }
        loadingReference = nil
        pullRequest = nil
        open(reference)
    }

    private func show(_ newPullRequest: PullRequest) {
        pullRequest = newPullRequest
        fileContents = [:]
        syntaxByPath = [:]
        selectedFilePath = nil
        selectedFilePath = newPullRequest.files.first?.path
    }

    // MARK: - Navigation

    /// Selects a file only if it's in the open pull request (folders in the sidebar are ignored).
    func selectFile(at path: String?) {
        guard let path, pullRequest?.file(at: path) != nil else { return }
        selectedFilePath = path
    }

    func selectAdjacentFile(offset: Int) {
        guard let paths = pullRequest?.files.map(\.path), let current = selectedFilePath,
              let index = paths.firstIndex(of: current) else { return }
        let next = index + offset
        if paths.indices.contains(next) {
            selectedFilePath = paths[next]
        }
    }

    // MARK: - File contents

    private func loadContent(ofFileAt path: String?) {
        guard let path, let pullRequest, let file = pullRequest.file(at: path) else { return }
        switch fileContents[path] {
        case .loading, .loaded, .binary: return
        case .failed, nil: break
        }
        fileContents[path] = .loading
        let loader = account.loader
        Task {
            let content: FileContent
            do {
                content = try await loader.content(of: file, in: pullRequest)
            } catch {
                content = .failed(error.localizedDescription)
            }
            guard self.pullRequest?.reference == pullRequest.reference else { return }
            fileContents[path] = content
            if case let .loaded(diff) = content {
                loadSyntax(for: diff)
            }
            if path == selectedFilePath {
                rebuildRows()
            }
        }
    }

    func retryLoadingSelectedFile() {
        guard let path = selectedFilePath else { return }
        fileContents[path] = nil
        loadContent(ofFileAt: path)
    }

    // MARK: - Rows

    func rebuildRows() {
        guard let diff = selectedFileDiff else {
            rows = []
            rowsVersion += 1
            return
        }
        var options = DiffRowOptions()
        options.layout = settings.diffLayout
        options.contextLines = settings.contextLines
        options.highlightsWordChanges = settings.highlightsWordChanges
        options.expandAll = expandAll
        options.expandedSegments = expandedSegments.union(segmentsWithFindMatches(in: diff))
        rows = DiffRowBuilder.rows(for: diff, options: options, attachments: attachments(forFileAt: diff.path))
        rowsVersion += 1
    }

    func expandSegment(_ index: Int) {
        expandedSegments.insert(index)
        rebuildRows()
    }

    private func attachments(forFileAt path: String) -> [Attachment] {
        let findingAttachments = findings(inFileAt: path).map {
            Attachment(id: Self.attachmentID(forFinding: $0.id), side: $0.side, lineIndex: $0.lineIndex)
        }
        let commentAttachments = comments(inFileAt: path).map {
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

    private func loadSyntax(for diff: FileDiff) {
        let language = SyntaxLanguage.detect(path: diff.path)
        Task {
            async let base = SyntaxDocument.parse(lines: diff.baseLines, language: language)
            async let head = SyntaxDocument.parse(lines: diff.headLines, language: language)
            syntaxByPath[diff.path] = (await base, await head)
            if diff.path == selectedFilePath {
                syntaxVersion += 1
            }
        }
    }

    // MARK: - Viewed files

    private func viewedKey(for path: String) -> String { "\(pullRequest?.id ?? ""):\(path)" }

    func isViewed(_ path: String) -> Bool {
        viewedFileKeys.contains(viewedKey(for: path))
    }

    var isSelectedFileViewed: Bool {
        selectedFilePath.map(isViewed) ?? false
    }

    var viewedFileCount: Int {
        pullRequest?.files.filter { isViewed($0.path) }.count ?? 0
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

    /// AI findings. Only the demo pull requests have any until AI review is built.
    func findings(inFileAt path: String) -> [ReviewFinding] {
        guard pullRequest?.reference.isDemo == true else { return [] }
        return findings.filter { $0.filePath == path }
    }

    func dismissFinding(_ finding: ReviewFinding) {
        findings.removeAll { $0.id == finding.id }
        rebuildRows()
    }

    func turnFindingIntoComment(_ finding: ReviewFinding) {
        guard let diff = selectedFileDiff, diff.path == finding.filePath else { return }
        let code = diff.lines(on: finding.side)[finding.lineIndex]
        dismissFinding(finding)
        startComment(on: CodeTarget(filePath: diff.path, side: finding.side, lines: finding.lineIndex...finding.lineIndex, code: code),
                     body: "**\(finding.title)**\n\n\(finding.body)")
    }

    // MARK: - Comments

    func comments(inFileAt path: String) -> [ReviewComment] {
        comments.filter { $0.pullRequest == pullRequest?.reference && $0.filePath == path }
    }

    func commentCount(forFileAt path: String) -> Int {
        comments(inFileAt: path).filter { !$0.isNew }.count
    }

    /// Comments written but not yet posted to GitHub.
    var pendingComments: [ReviewComment] {
        comments.filter { $0.pullRequest == pullRequest?.reference && $0.isPending }
    }

    func startComment(on target: CodeTarget, body: String = "") {
        guard let reference = pullRequest?.reference else { return }
        let comment = ReviewComment(id: UUID(), pullRequest: reference, filePath: target.filePath,
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

    // MARK: - Submitting a review

    var canSubmitReview: Bool {
        pullRequest?.reference.isDemo == false && account.isSignedIn
    }

    /// Posts the review with every pending comment, then marks those comments as submitted.
    func submitReview(event: GitHubReviewSubmission.Event, body: String) async throws {
        guard let pullRequest, let client = account.client, !pullRequest.reference.isDemo else {
            throw PullRequestLoader.LoadError.notSignedIn
        }
        let pending = pendingComments
        let review = GitHubReviewSubmission(commitID: pullRequest.headSHA, event: event, body: body, comments: pending.map { comment in
            // GitHub numbers lines from 1.
            let lines = (comment.lines.lowerBound + 1)...(comment.lines.upperBound + 1)
            return GitHubReviewSubmission.Comment(path: comment.filePath, body: comment.body,
                                                  side: comment.side == .head ? .right : .left, lines: lines)
        })

        isSubmittingReview = true
        defer { isSubmittingReview = false }
        try await client.submitReview(review, repository: pullRequest.reference.repository, number: pullRequest.number)
        for comment in pending {
            updateComment(comment.id) { $0.isSubmitted = true }
        }
    }

    private func updateComment(_ id: UUID, _ change: (inout ReviewComment) -> Void) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        change(&comments[index])
    }
}

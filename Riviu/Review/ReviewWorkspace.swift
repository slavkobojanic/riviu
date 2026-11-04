import Foundation
import Observation
import RiviuAI
import RiviuDiff
import RiviuGitHub
import RiviuSyntax

/// What can appear between diff lines.
enum InlineItem {
    case finding(ReviewFinding)
    case comment(ReviewComment)
    case thread(GitHubReviewThread)
}

/// Asks the diff view to move to the next or previous find match. `count` changes on every request.
struct FindStep: Equatable {
    var count = 0
    var forward = true
}

/// A line the diff view should scroll to. `id` changes on every request.
struct LineToReveal: Equatable {
    let id = UUID()
    let side: DiffSide
    let lineIndex: Int
}

/// A place in a review that Back and Forward return to: a pull request's overview (no file) or one of its files.
struct ReviewLocation: Equatable {
    let pullRequest: PullRequestReference
    let filePath: String?
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

    /// True while the pull request's overview is shown instead of a file.
    private(set) var showsOverview = false

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

    private(set) var comments: [ReviewComment] = []
    private(set) var viewedFileKeys: Set<String> = []
    /// Files GitHub says changed after you marked them viewed.
    private(set) var changedSinceViewedPaths: Set<String> = []
    /// Conversations already on the pull request, from GitHub.
    private(set) var threads: [GitHubReviewThread] = []
    /// Why viewed files or conversations couldn't be loaded or saved.
    private(set) var syncErrorMessage: String?
    private(set) var isSubmittingReview = false

    var isFindVisible = false
    var findQuery = "" {
        didSet {
            if findQuery != oldValue { rebuildRows() }
        }
    }
    private(set) var findStep = FindStep()
    private(set) var lineToReveal: LineToReveal?
    var findStatus = FindStatus()

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let account: GitHubAccount
    @ObservationIgnored private let aiReviews: AIReviewStore
    @ObservationIgnored private var openTask: Task<Void, Never>?
    /// The pull request's GraphQL ID, needed to mark files as viewed on GitHub.
    @ObservationIgnored private var gitHubPullRequestID: String?
    /// Where "Next Conversation" continues from.
    @ObservationIgnored private var lastRevealedThreadID: String?
    @ObservationIgnored private var expandedSegments: Set<Int> = []
    /// Back and Forward history, oldest first.
    private(set) var backHistory: [ReviewLocation] = []
    private(set) var forwardHistory: [ReviewLocation] = []
    /// Where to land once the pull request being loaded for Back or Forward arrives.
    @ObservationIgnored private var locationToRestore: ReviewLocation?
    @ObservationIgnored private var syntaxByPath: [String: (base: SyntaxDocument, head: SyntaxDocument)] = [:]

    init(settings: AppSettings, account: GitHubAccount, aiReviews: AIReviewStore) {
        self.settings = settings
        self.account = account
        self.aiReviews = aiReviews
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
        locationToRestore = nil
        load(reference)
    }

    private func load(_ reference: PullRequestReference) {
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
                guard !Task.isCancelled else { return }
                openErrorMessage = error.localizedDescription
            }
            loadingReference = nil
        }
    }

    func retryOpening() {
        guard let reference = loadingReference ?? pullRequest?.reference else { return }
        loadingReference = nil
        pullRequest = nil
        load(reference)
    }

    private func show(_ newPullRequest: PullRequest) {
        let previous = location
        pullRequest = newPullRequest
        fileContents = [:]
        syntaxByPath = [:]
        threads = []
        changedSinceViewedPaths = []
        syncErrorMessage = nil
        gitHubPullRequestID = nil
        loadGitHubState(for: newPullRequest.reference)
        selectedFilePath = nil
        // The first file loads in the background while the overview is shown.
        selectedFilePath = newPullRequest.files.first?.path
        showsOverview = true
        if let restore = locationToRestore, restore.pullRequest == newPullRequest.reference {
            locationToRestore = nil
            apply(restore)
        } else if let previous, previous.pullRequest != newPullRequest.reference {
            remember(previous)
        }
    }

    // MARK: - Navigation

    func showOverview() {
        navigating { showsOverview = true }
    }

    /// Selects a file only if it's in the open pull request (folders in the sidebar are ignored).
    func selectFile(at path: String?) {
        guard let path, pullRequest?.file(at: path) != nil else { return }
        navigating {
            selectedFilePath = path
            showsOverview = false
        }
    }

    /// From the overview, the next file is the one already selected.
    func selectAdjacentFile(offset: Int) {
        if showsOverview {
            navigating { showsOverview = false }
            return
        }
        guard let paths = pullRequest?.files.map(\.path), let current = selectedFilePath,
              let index = paths.firstIndex(of: current) else { return }
        let next = index + offset
        if paths.indices.contains(next) {
            navigating { selectedFilePath = paths[next] }
        }
    }

    // MARK: - Back and Forward

    /// The overview or file on screen.
    var location: ReviewLocation? {
        guard let pullRequest else { return nil }
        return ReviewLocation(pullRequest: pullRequest.reference, filePath: showsOverview ? nil : selectedFilePath)
    }

    var canGoBack: Bool { !backHistory.isEmpty }
    var canGoForward: Bool { !forwardHistory.isEmpty }

    func goBack() {
        guard let current = destination, let target = backHistory.popLast() else { return }
        forwardHistory.append(current)
        go(to: target)
    }

    func goForward() {
        guard let current = destination, let target = forwardHistory.popLast() else { return }
        backHistory.append(current)
        go(to: target)
    }

    /// Where Back or Forward is headed, while its pull request loads; otherwise what's on screen.
    private var destination: ReviewLocation? {
        if let locationToRestore, locationToRestore.pullRequest == loadingReference { return locationToRestore }
        return location
    }

    private func go(to target: ReviewLocation) {
        if target.pullRequest == pullRequest?.reference {
            // Stop loading any other pull request; the target is already open.
            openTask?.cancel()
            loadingReference = nil
            openErrorMessage = nil
            locationToRestore = nil
            apply(target)
        } else {
            locationToRestore = target
            load(target.pullRequest)
        }
    }

    private func apply(_ target: ReviewLocation) {
        if let path = target.filePath, pullRequest?.file(at: path) != nil {
            selectedFilePath = path
            showsOverview = false
        } else {
            showsOverview = true
        }
    }

    /// Makes a change of location that Back returns from.
    private func navigating(_ change: () -> Void) {
        let before = location
        change()
        if let before, before != location {
            remember(before)
        }
    }

    private func remember(_ location: ReviewLocation) {
        backHistory.append(location)
        if backHistory.count > 200 { backHistory.removeFirst() }
        forwardHistory = []
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
        let threadAttachments = threads(inFileAt: path).compactMap { thread in
            thread.lineIndex.map { Attachment(id: Self.attachmentID(forThread: thread.id), side: thread.side, lineIndex: $0) }
        }
        return findingAttachments + threadAttachments + commentAttachments
    }

    private static func attachmentID(forFinding id: String) -> AttachmentID { AttachmentID("finding:" + id) }
    private static func attachmentID(forComment id: UUID) -> AttachmentID { AttachmentID("comment:" + id.uuidString) }
    private static func attachmentID(forThread id: String) -> AttachmentID { AttachmentID("thread:" + id) }

    func inlineItem(for id: AttachmentID) -> InlineItem? {
        if let thread = threads.first(where: { Self.attachmentID(forThread: $0.id) == id }) {
            return .thread(thread)
        }
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

    func isChangedSinceViewed(_ path: String) -> Bool {
        changedSinceViewedPaths.contains(path)
    }

    /// Also marks the file on GitHub, and undoes the change if GitHub refuses it.
    func toggleViewedForSelectedFile() {
        guard let path = selectedFilePath else { return }
        let isNowViewed = !isViewed(path)
        setViewed(isNowViewed, path: path)
        changedSinceViewedPaths.remove(path)
        guard let client = account.client, let pullRequestID = gitHubPullRequestID else { return }
        Task {
            do {
                try await client.setFileViewed(isNowViewed, path: path, pullRequestID: pullRequestID)
            } catch {
                setViewed(!isNowViewed, path: path)
                syncErrorMessage = "Couldn't mark \((path as NSString).lastPathComponent) on GitHub: \(error.localizedDescription)"
            }
        }
    }

    private func setViewed(_ isViewed: Bool, path: String) {
        if isViewed {
            viewedFileKeys.insert(viewedKey(for: path))
        } else {
            viewedFileKeys.remove(viewedKey(for: path))
        }
    }

    // MARK: - Syncing with GitHub

    /// Loads which files you've viewed and the existing conversations.
    private func loadGitHubState(for reference: PullRequestReference) {
        guard !reference.isDemo, let client = account.client else { return }
        Task {
            async let viewedFiles = client.viewedFiles(repository: reference.repository, number: reference.number)
            async let loadedThreads = client.reviewThreads(repository: reference.repository, number: reference.number)
            do {
                let viewed = try await viewedFiles
                guard pullRequest?.reference == reference else { return }
                gitHubPullRequestID = viewed.pullRequestID
                for (path, state) in viewed.states {
                    setViewed(state == .viewed, path: path)
                    if state == .dismissed {
                        changedSinceViewedPaths.insert(path)
                    }
                }
                threads = try await loadedThreads
                rebuildRows()
            } catch {
                guard pullRequest?.reference == reference else { return }
                syncErrorMessage = "Couldn't load viewed files and conversations from GitHub: \(error.localizedDescription)"
            }
        }
    }

    private func reloadThreads() async {
        guard let reference = pullRequest?.reference, !reference.isDemo, let client = account.client else { return }
        do {
            let loaded = try await client.reviewThreads(repository: reference.repository, number: reference.number)
            guard pullRequest?.reference == reference else { return }
            threads = loaded
            rebuildRows()
        } catch {
            syncErrorMessage = "Couldn't reload conversations: \(error.localizedDescription)"
        }
    }

    // MARK: - Conversations

    /// Threads shown in a file: those still on a line of the latest diff.
    func threads(inFileAt path: String) -> [GitHubReviewThread] {
        let inFile = threads.filter { $0.path == path }
        guard case let .loaded(diff) = fileContents[path] else { return inFile }
        return inFile.filter { thread in
            thread.lineIndex.map { diff.lines(on: thread.side).indices.contains($0) } ?? false
        }
    }

    func unresolvedThreadCount(forFileAt path: String) -> Int {
        threads.filter { $0.path == path && !$0.isResolved }.count
    }

    /// Unresolved threads that can be shown in the diff, in file order.
    var unresolvedThreads: [GitHubReviewThread] {
        let order = pullRequest?.files.map(\.path) ?? []
        return threads
            .filter { !$0.isResolved && $0.lineIndex != nil }
            .sorted { (order.firstIndex(of: $0.path) ?? 0, $0.lineIndex ?? 0) < (order.firstIndex(of: $1.path) ?? 0, $1.lineIndex ?? 0) }
    }

    func reveal(_ thread: GitHubReviewThread) {
        guard let lineIndex = thread.lineIndex else { return }
        reveal(lineIndex: lineIndex, on: thread.side, inFileAt: thread.path)
        lastRevealedThreadID = thread.id
    }

    /// Jumps to the next or previous unresolved conversation, wrapping around.
    func revealAdjacentThread(offset: Int) {
        let unresolved = unresolvedThreads
        guard !unresolved.isEmpty else { return }
        let current = unresolved.firstIndex { $0.id == lastRevealedThreadID }
        let next = current.map { ($0 + offset + unresolved.count) % unresolved.count } ?? (offset > 0 ? 0 : unresolved.count - 1)
        reveal(unresolved[next])
    }

    func reply(to thread: GitHubReviewThread, body: String) async throws {
        guard let client = account.client else { throw PullRequestLoader.LoadError.notSignedIn }
        _ = try await client.reply(to: thread.id, body: body)
        await reloadThreads()
    }

    func setResolved(_ isResolved: Bool, thread: GitHubReviewThread) async throws {
        guard let client = account.client else { throw PullRequestLoader.LoadError.notSignedIn }
        try await client.setThreadResolved(isResolved, threadID: thread.id)
        await reloadThreads()
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

    /// The open pull request's AI findings.
    var findings: [ReviewFinding] {
        guard let reference = pullRequest?.reference else { return [] }
        return aiReviews.review(for: reference)?.findings ?? []
    }

    /// Findings on lines that exist in the file; an AI can name a line that isn't there.
    func findings(inFileAt path: String) -> [ReviewFinding] {
        let inFile = findings.filter { $0.filePath == path }
        guard case let .loaded(diff) = fileContents[path] else { return inFile }
        return inFile.filter { diff.lines(on: $0.side).indices.contains($0.lineIndex) }
    }

    /// Opens the file a finding is in and scrolls to it.
    func reveal(_ finding: ReviewFinding) {
        reveal(lineIndex: finding.lineIndex, on: finding.side, inFileAt: finding.filePath)
    }

    /// Opens a file and scrolls to a line.
    func reveal(lineIndex: Int, on side: DiffSide, inFileAt path: String) {
        selectFile(at: path)
        lineToReveal = LineToReveal(side: side, lineIndex: lineIndex)
    }

    func dismissFinding(_ finding: ReviewFinding) {
        guard let reference = pullRequest?.reference else { return }
        aiReviews.dismissFinding(finding.id, in: reference)
        rebuildRows()
    }

    /// Opens a comment with the finding's text, and its suggested fix as a GitHub suggestion.
    /// Opens the question's line with a comment that asks it.
    func ask(_ question: AuthorQuestion) {
        reveal(lineIndex: question.lineIndex, on: .head, inFileAt: question.filePath)
        var code = ""
        if case let .loaded(diff) = fileContents[question.filePath], diff.headLines.indices.contains(question.lineIndex) {
            code = diff.headLines[question.lineIndex]
        }
        startComment(on: CodeTarget(filePath: question.filePath, side: .head, lines: question.lineIndex...question.lineIndex, code: code),
                     body: "**question:** \(question.question)")
    }

    func turnFindingIntoComment(_ finding: ReviewFinding) {
        guard let diff = selectedFileDiff, diff.path == finding.filePath else { return }
        let fileLines = diff.lines(on: finding.side)
        guard fileLines.indices.contains(finding.lines.upperBound) else { return }
        var body = "**\(finding.title)**\n\n\(finding.body)"
        if let suggestion = finding.suggestion {
            body += "\n\n```suggestion\n\(suggestion)\n```"
        }
        let code = fileLines[finding.lines].joined(separator: "\n")
        dismissFinding(finding)
        startComment(on: CodeTarget(filePath: diff.path, side: finding.side, lines: finding.lines, code: code), body: body)
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

    /// An AI rewrite of a draft comment, in the tone of your earlier comments on this pull request.
    func polish(_ draft: String, for comment: ReviewComment) async throws -> String {
        let login = account.user?.login
        let examples = threads.flatMap(\.allComments)
            .filter { login != nil && $0.author?.login == login }
            .suffix(5)
            .map { String($0.body.prefix(300)) }
        let provider = try AISetup.makeProvider(for: .chat, settings: settings)
        let request = ReviewPrompts.polishRequest(draft: draft, comment: comment, examples: Array(examples))
        return try await provider.reply(to: request).trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Posted comments come back from GitHub as conversations.
        let postedIDs = Set(pending.map(\.id))
        comments.removeAll { postedIDs.contains($0.id) }
        await reloadThreads()
    }

    private func updateComment(_ id: UUID, _ change: (inout ReviewComment) -> Void) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        change(&comments[index])
    }
}

extension GitHubReviewThread {
    var side: DiffSide { diffSide == "LEFT" ? .base : .head }
    /// 0-based, or nil when the thread's lines are gone from the latest diff.
    var lineIndex: Int? { line.map { $0 - 1 } }
}

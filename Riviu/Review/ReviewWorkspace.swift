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
    case annotation(GitHubCheckAnnotation)
}

/// What the AI thinks broke a CI job, and the line it suspects.
struct FailureExplanation {
    let markdown: String
    let suspectPath: String?
    /// 0-based, in the new file.
    let suspectLineIndex: Int?
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

/// What changed since you last reviewed the pull request.
struct SinceLastReview {
    /// The commit your last review was on.
    let reviewedSHA: String
    let reviewedAt: Date
    let commitCount: Int
    /// After a rebase or force-push the changes can include work from the base branch.
    let isRebased: Bool
    let files: [ChangedFile]
}

/// Which match is selected (0-based, or -1) out of how many, as reported by the diff view.
struct FindStatus: Equatable {
    var current = -1
    var total = 0
}

/// What the sidebar shows: the pull request list, or the open pull request's files.
enum SidebarPage {
    case pullRequests
    case files
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

    /// Opening a pull request switches this to its files; the sidebar's back button and
    /// Review > Show Pull Requests switch it back.
    var sidebarPage = SidebarPage.pullRequests

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

    /// The guided tour card in focus, or nil when not touring. One past the last stop is the closing card.
    private(set) var tourCardIndex: Int?
    /// True while looking at a tour stop in the diff, with a button back to the tour.
    private(set) var isTourPaused = false
    /// Set to show the review sheet with this verdict picked; nil when it's closed.
    var reviewSheetVerdict: GitHubReviewSubmission.Event?

    /// Collapses hunks that only move, rename or reformat code.
    var hidesCosmeticChanges = false {
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
    /// Set when there are new commits since your last review.
    private(set) var sinceLastReview: SinceLastReview?
    /// True while the diff shows only what changed since your last review.
    private(set) var showsChangesSinceLastReview = false
    /// CI checks on the head commit, and the messages they left on lines.
    private(set) var checkRuns: [GitHubCheckRun] = []
    private(set) var annotations: [GitHubCheckAnnotation] = []
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
    @ObservationIgnored private let rules: ReviewRuleStore
    @ObservationIgnored let codeIndexes: CodeIndexStore
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
    @ObservationIgnored private var structuralChangesByPath: [String: [Int: StructuralChange]] = [:]

    init(settings: AppSettings, account: GitHubAccount, aiReviews: AIReviewStore, rules: ReviewRuleStore, codeIndexes: CodeIndexStore) {
        self.codeIndexes = codeIndexes
        self.settings = settings
        self.account = account
        self.aiReviews = aiReviews
        self.rules = rules
    }

    var selectedFile: ChangedFile? {
        selectedFilePath.flatMap(visibleFile)
    }

    /// The files the sidebar lists: all of them, or only those changed since your last review.
    var visibleFiles: [ChangedFile] {
        if showsChangesSinceLastReview, let sinceLastReview { return sinceLastReview.files }
        return pullRequest?.files ?? []
    }

    func visibleFile(at path: String) -> ChangedFile? {
        visibleFiles.first { $0.path == path }
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
        sidebarPage = .files
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
        // A pull request that has never had an AI review gets one, if automatic reviews are on.
        let reference = newPullRequest.reference
        if settings.reviewsNewRequestsWithAI, aiReviews.review(for: reference) == nil, aiReviews.activity(for: reference) == nil {
            aiReviews.start(for: newPullRequest)
        }
        fileContents = [:]
        syntaxByPath = [:]
        structuralChangesByPath = [:]
        threads = []
        tourCardIndex = nil
        isTourPaused = false
        sinceLastReview = nil
        showsChangesSinceLastReview = false
        checkRuns = []
        annotations = []
        loadChecks(for: newPullRequest)
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

    func showPullRequestList() {
        sidebarPage = .pullRequests
    }

    func showOverview() {
        pauseTourIfTouring()
        navigating { showsOverview = true }
    }

    /// Selects a file only if it's in the open pull request (folders in the sidebar are ignored).
    func selectFile(at path: String?) {
        guard let path, visibleFile(at: path) != nil else { return }
        pauseTourIfTouring()
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
        let paths = visibleFiles.map(\.path)
        guard let current = selectedFilePath, let index = paths.firstIndex(of: current) else { return }
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
        if let path = target.filePath, visibleFile(at: path) != nil {
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
        guard let path, let pullRequest, let file = visibleFile(at: path) else { return }
        switch fileContents[path] {
        case .loading, .loaded, .binary: return
        case .failed, nil: break
        }
        fileContents[path] = .loading
        let loader = account.loader
        let baseSHA = diffBaseSHA
        Task {
            let content: FileContent
            do {
                content = try await loader.content(of: file, in: pullRequest, baseSHA: baseSHA)
            } catch {
                content = .failed(error.localizedDescription)
            }
            // Drop it if the pull request or the comparison changed while it loaded.
            guard self.pullRequest?.reference == pullRequest.reference, diffBaseSHA == baseSHA else { return }
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

    // MARK: - Changes since your last review

    /// The commit the diff is measured from.
    private var diffBaseSHA: String {
        if showsChangesSinceLastReview, let sinceLastReview { return sinceLastReview.reviewedSHA }
        return pullRequest?.baseSHA ?? ""
    }

    /// Switches between the whole pull request and only what changed since your last review.
    func setShowsChangesSinceLastReview(_ shows: Bool) {
        guard shows != showsChangesSinceLastReview, sinceLastReview != nil || !shows else { return }
        showsChangesSinceLastReview = shows
        fileContents = [:]
        syntaxByPath = [:]
        structuralChangesByPath = [:]
        let path = selectedFilePath.flatMap(visibleFile)?.path ?? visibleFiles.first?.path
        selectedFilePath = nil
        selectedFilePath = path
    }

    /// The login whose last review "since your last review" is measured from.
    private var reviewerLogin: String? {
        #if DEBUG
        if let login = UserDefaults.standard.string(forKey: "debugReviewer") { return login }
        #endif
        return account.user?.login
    }

    private func loadSinceLastReview(for pullRequest: PullRequest, client: GitHubClient) async {
        let reference = pullRequest.reference
        guard let login = reviewerLogin,
              let reviews = try? await client.reviews(repository: reference.repository, number: reference.number),
              let last = reviews.last(where: { $0.user?.login == login && $0.submittedAt != nil && $0.commitId != nil }),
              let reviewedSHA = last.commitId, let reviewedAt = last.submittedAt, reviewedSHA != pullRequest.headSHA,
              let comparison = try? await client.compare(repository: reference.repository, base: reviewedSHA, head: pullRequest.headSHA)
        else { return }
        // Only files that are still part of the pull request.
        let files = (comparison.files ?? []).map(PullRequestLoader.changedFile).filter { pullRequest.file(at: $0.path) != nil }
        guard self.pullRequest?.reference == reference, !files.isEmpty else { return }
        sinceLastReview = SinceLastReview(reviewedSHA: reviewedSHA, reviewedAt: reviewedAt, commitCount: comparison.totalCommits,
                                          isRebased: comparison.status != "ahead", files: files)
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
        options.structuralChanges = structuralChanges(for: diff)
        options.hidesCosmeticChanges = hidesCosmeticChanges
        rows = DiffRowBuilder.rows(for: diff, options: options, attachments: attachments(forFileAt: diff.path))
        rowsVersion += 1
    }

    /// Worked out once per file, since it compares every hunk with every other.
    private func structuralChanges(for diff: FileDiff) -> [Int: StructuralChange] {
        if let cached = structuralChangesByPath[diff.path] { return cached }
        let changes = StructuralChanges.classify(diff)
        structuralChangesByPath[diff.path] = changes
        return changes
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
        let annotationAttachments = annotations.indices.compactMap { index -> Attachment? in
            let annotation = annotations[index]
            guard annotation.path == path, let lineIndex = annotationLineIndex(annotation, inFileAt: path) else { return nil }
            return Attachment(id: Self.attachmentID(forAnnotation: index), side: .head, lineIndex: lineIndex)
        }
        let all = findingAttachments + annotationAttachments + threadAttachments + commentAttachments
        // The base side is a different commit while comparing with your last review, so its line numbers don't match.
        return showsChangesSinceLastReview ? all.filter { $0.side == .head } : all
    }

    /// Annotations name 1-based lines of the head version; some point outside the file.
    private func annotationLineIndex(_ annotation: GitHubCheckAnnotation, inFileAt path: String) -> Int? {
        guard case let .loaded(diff) = fileContents[path] else { return nil }
        let index = annotation.endLine - 1
        return diff.headLines.indices.contains(index) ? index : nil
    }

    private static func attachmentID(forFinding id: String) -> AttachmentID { AttachmentID("finding:" + id) }
    private static func attachmentID(forComment id: UUID) -> AttachmentID { AttachmentID("comment:" + id.uuidString) }
    private static func attachmentID(forThread id: String) -> AttachmentID { AttachmentID("thread:" + id) }
    private static func attachmentID(forAnnotation index: Int) -> AttachmentID { AttachmentID("annotation:\(index)") }

    func inlineItem(for id: AttachmentID) -> InlineItem? {
        if let thread = threads.first(where: { Self.attachmentID(forThread: $0.id) == id }) {
            return .thread(thread)
        }
        if let index = annotations.indices.first(where: { Self.attachmentID(forAnnotation: $0) == id }) {
            return .annotation(annotations[index])
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
        guard let client = account.client else { return }
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
                if let pullRequest {
                    await loadSinceLastReview(for: pullRequest, client: client)
                }
            } catch {
                guard pullRequest?.reference == reference else { return }
                syncErrorMessage = "Couldn't load viewed files and conversations from GitHub: \(error.localizedDescription)"
            }
        }
    }

    private func reloadThreads() async {
        guard let reference = pullRequest?.reference, let client = account.client else { return }
        do {
            let loaded = try await client.reviewThreads(repository: reference.repository, number: reference.number)
            guard pullRequest?.reference == reference else { return }
            threads = loaded
            rebuildRows()
        } catch {
            syncErrorMessage = "Couldn't reload conversations: \(error.localizedDescription)"
        }
    }

    // MARK: - Guided tour

    var tour: ReviewTour? {
        pullRequest.flatMap(aiReviews.tour)
    }

    var isTouring: Bool { tourCardIndex != nil }

    /// The stop in focus, or nil on the closing card.
    var currentTourStop: TourStop? {
        guard let tour, let tourCardIndex, tour.stops.indices.contains(tourCardIndex) else { return nil }
        return tour.stops[tourCardIndex]
    }

    func startTour(at index: Int = 0) {
        guard tour != nil else { return }
        setShowsChangesSinceLastReview(false)
        isTourPaused = false
        focusTourCard(index)
    }

    func endTour() {
        tourCardIndex = nil
        isTourPaused = false
    }

    /// The tour's stops, then the closing card.
    func focusTourCard(_ index: Int) {
        guard let tour else { return }
        tourCardIndex = min(max(index, 0), tour.stops.count)
    }

    func advanceTour(by offset: Int) {
        guard let tourCardIndex else { return }
        focusTourCard(tourCardIndex + offset)
    }

    /// Shows the focused stop's lines in the diff, with a way back to the tour.
    func openCurrentTourStop() {
        guard let stop = currentTourStop else { return }
        isTourPaused = true
        reveal(lineIndex: stop.lines.lowerBound - 1, on: stop.side, inFileAt: stop.filePath)
    }

    func returnToTour() {
        isTourPaused = false
    }

    /// Going to a file or the overview during a tour shows it, keeping the tour to come back to.
    private func pauseTourIfTouring() {
        if isTouring { isTourPaused = true }
    }

    // MARK: - Code navigation

    /// The index of the whole repository at the head commit, once it's built.
    var codeIndex: SymbolIndex? {
        pullRequest.flatMap(codeIndexes.index)
    }

    var codeIndexState: CodeIndexStore.State? {
        pullRequest.flatMap(codeIndexes.state)
    }

    /// Downloads and indexes the repository the first time the hot path or Go to Definition is used.
    func prepareCodeIndex() {
        guard let pullRequest else { return }
        let loader = account.loader
        codeIndexes.prepare(pullRequest) {
            await Self.headVersions(of: pullRequest, loader: loader)
        }
    }

    /// The pull request's own files, for when the whole repository can't be downloaded.
    private static func headVersions(of pullRequest: PullRequest, loader: PullRequestLoader) async -> [(path: String, text: String)] {
        var files: [(path: String, text: String)] = []
        for file in pullRequest.files.prefix(150) where file.status != .deleted {
            if case let .loaded(diff)? = try? await loader.content(of: file, in: pullRequest) {
                files.append((file.path, diff.headLines.joined(separator: "\n")))
            }
        }
        return files
    }

    func explainHotPath(focus: String, code: String, callers: [HotPathItem], callees: [HotPathItem]) async throws -> String {
        guard let pullRequest else { return "" }
        let provider = try AISetup.makeProvider(for: .explain, settings: settings)
        let request = ReviewPrompts.hotPathRequest(focus: focus, code: code, callers: callers, callees: callees, pullRequest: pullRequest)
        return try await provider.reply(to: request)
    }

    /// Jumps to a name's definition when it's in the pull request and there's only one. Returns false when the
    /// definitions should be listed instead, including while the index is still being built.
    func jumpToDefinition(of name: String) -> Bool {
        guard let index = codeIndex else { return false }
        let definitions = index.definitions(named: name)
        guard definitions.count == 1, let definition = definitions.first, pullRequest?.file(at: definition.path) != nil else { return false }
        reveal(lineIndex: definition.lines.lowerBound, on: .head, inFileAt: definition.path)
        return true
    }

    /// 0-based head lines the pull request added, for marking changed code on the hot path.
    func changedHeadLines(inFileAt path: String) -> Set<Int> {
        guard let patch = pullRequest?.file(at: path)?.patch else { return [] }
        return Set(PatchHunk.hunks(in: patch).flatMap(\.addedLines).map { $0 - 1 })
    }

    /// Shows code from the index: jumps to it if the file is in the pull request, which is the only code the diff can show.
    func open(_ excerpt: CodeExcerpt) -> Bool {
        guard pullRequest?.file(at: excerpt.path) != nil else { return false }
        reveal(lineIndex: excerpt.focusLine ?? excerpt.firstLine, on: .head, inFileAt: excerpt.path)
        return true
    }

    // MARK: - CI checks

    func annotationCount(forFileAt path: String) -> Int {
        annotations.filter { $0.path == path && $0.annotationLevel != "notice" }.count
    }

    private func loadChecks(for pullRequest: PullRequest) {
        let reference = pullRequest.reference
        guard let client = account.client else { return }
        Task {
            guard let runs = try? await client.checkRuns(repository: reference.repository, commit: pullRequest.headSHA),
                  self.pullRequest?.reference == reference else { return }
            checkRuns = runs.sorted { ($0.isFailure ? 0 : 1, $0.name) < ($1.isFailure ? 0 : 1, $1.name) }
            var loaded: [GitHubCheckAnnotation] = []
            for run in runs.filter({ $0.output.annotationsCount > 0 }).prefix(10) {
                loaded += (try? await client.annotations(repository: reference.repository, checkRunID: run.id)) ?? []
            }
            guard self.pullRequest?.reference == reference else { return }
            annotations = loaded
            rebuildRows()
        }
    }

    /// Asks the AI why a job failed, from the end of its log and the diff.
    func explainFailure(of run: GitHubCheckRun) async throws -> FailureExplanation {
        guard let pullRequest, let client = account.client else { throw PullRequestLoader.LoadError.notSignedIn }
        let log = try await client.jobLogTail(repository: pullRequest.reference.repository, jobID: run.id)
        let provider = try AISetup.makeProvider(for: .explain, settings: settings)
        let request = ReviewPrompts.failureRequest(checkName: run.name, log: log, pullRequest: pullRequest)
        return FailureExplanation(reply: try await provider.reply(to: request), pullRequest: pullRequest)
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

    /// The open pull request's AI findings that still need attention.
    var findings: [ReviewFinding] {
        guard let reference = pullRequest?.reference else { return [] }
        return (aiReviews.review(for: reference)?.findings ?? []).filter { !$0.isAddressed }
    }

    /// Findings from an earlier review that new commits fixed.
    var addressedFindings: [ReviewFinding] {
        guard let reference = pullRequest?.reference else { return [] }
        return (aiReviews.review(for: reference)?.findings ?? []).filter(\.isAddressed)
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

    /// A reason is remembered, so Riviu can later suggest a rule for this repository.
    func dismissFinding(_ finding: ReviewFinding, reason: DismissReason? = nil) {
        guard let reference = pullRequest?.reference else { return }
        if let reason {
            rules.recordDismissal(of: finding, in: reference.repository, reason: reason)
        }
        aiReviews.dismissFinding(finding.id, in: reference)
        rebuildRows()
    }

    /// Dismisses a finding and tells future AI reviews of this repository not to flag similar ones.
    func dismissFinding(_ finding: ReviewFinding, addingRule rule: String) {
        guard let reference = pullRequest?.reference else { return }
        rules.addRule(rule, for: reference.repository)
        dismissFinding(finding, reason: .notAProblem)
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
        // GitHub's base side is the pull request's base, not the commit you last reviewed.
        guard let reference = pullRequest?.reference, !(showsChangesSinceLastReview && target.side == .base) else { return }
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
        pullRequest != nil && account.isSignedIn
    }

    /// Posts the review with every pending comment, then marks those comments as submitted.
    func submitReview(event: GitHubReviewSubmission.Event, body: String) async throws {
        guard let pullRequest, let client = account.client else {
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

extension FailureExplanation {
    /// The reply ends with "Suspect: path:line" when the AI can point at a changed line.
    init(reply: String, pullRequest: PullRequest) {
        var lines = reply.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        var path: String?
        var lineIndex: Int?
        if let last = lines.last, let match = last.wholeMatch(of: #/(?i)\s*suspect:\s*`?([^`:\s]+):(\d+)`?\s*/#),
           pullRequest.file(at: String(match.1)) != nil, let line = Int(match.2), line > 0 {
            path = String(match.1)
            lineIndex = line - 1
            lines.removeLast()
        }
        self.init(markdown: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                  suspectPath: path, suspectLineIndex: lineIndex)
    }
}

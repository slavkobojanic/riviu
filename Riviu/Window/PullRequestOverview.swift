import RiviuAI
import RiviuGitHub
import RiviuMarkdown
import SwiftUI

/// The high-level view of a pull request: what it is, the AI's summary and findings, and its description.
struct PullRequestOverview: View {
    let pullRequest: PullRequest
    let workspace: ReviewWorkspace
    let aiReviews: AIReviewStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                OverviewHeader(pullRequest: pullRequest)
                if let message = workspace.syncErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if let sinceLastReview = workspace.sinceLastReview {
                    SinceLastReviewBanner(workspace: workspace, sinceLastReview: sinceLastReview)
                }
                if !workspace.checkRuns.isEmpty {
                    ChecksSection(workspace: workspace)
                }
                AISummaryCard(pullRequest: pullRequest, aiReviews: aiReviews)
                if let review = currentReview {
                    if let specCheck = review.specCheck {
                        SpecCheckSection(specCheck: specCheck)
                    }
                    if let questions = review.questions, !questions.isEmpty {
                        QuestionsSection(questions: questions, workspace: workspace)
                    }
                }
                if !workspace.findings.isEmpty {
                    FindingsSection(findings: workspace.findings, workspace: workspace)
                }
                if !workspace.addressedFindings.isEmpty {
                    AddressedFindingsSection(findings: workspace.addressedFindings)
                }
                if !workspace.threads.isEmpty {
                    ConversationsSection(workspace: workspace)
                }
                DescriptionSection(description: pullRequest.summary)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
    }

    /// The finished review, hidden while a new one is running.
    private var currentReview: AIReview? {
        guard aiReviews.activity(for: pullRequest.reference) == nil else { return nil }
        return aiReviews.review(for: pullRequest.reference)
    }
}

private struct OverviewHeader: View {
    let pullRequest: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pullRequest.reference.isDemo ? "Demo #\(String(pullRequest.number))" : pullRequest.reference.id)
                .font(.subheadline.weight(.semibold))
            Text(pullRequest.title)
                .font(.largeTitle.weight(.bold))
                .textSelection(.enabled)
            HStack(spacing: 16) {
                Label(pullRequest.author, systemImage: "person")
                Label("\(pullRequest.headBranch) → \(pullRequest.baseBranch)", systemImage: "arrow.triangle.branch")
                    .lineLimit(1)
                Label("\(pullRequest.files.count) files", systemImage: "doc.on.doc")
                HStack(spacing: 6) {
                    Text("+\(pullRequest.additions)").foregroundStyle(.green)
                    Text("−\(pullRequest.deletions)").foregroundStyle(.red)
                }
                .monospacedDigit()
            }
            .font(.callout)
        }
    }
}

/// The AI's summary, or a way to get one.
private struct AISummaryCard: View {
    let pullRequest: PullRequest
    let aiReviews: AIReviewStore
    @Environment(AppSettings.self) private var settings

    private var review: AIReview? { aiReviews.review(for: pullRequest.reference) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("AI Summary", systemImage: "sparkles")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
                Spacer()
                if let review, aiReviews.activity(for: pullRequest.reference) == nil {
                    SeverityBadge(severity: review.risk, label: "\(review.risk.rawValue) risk")
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var content: some View {
        switch aiReviews.activity(for: pullRequest.reference) {
        case .queued:
            Label("A summary is coming once the AI finishes the reviews ahead of this one.", systemImage: "clock")
        case let .reviewing(author):
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Generating a summary with \(author)… This can take a minute or two. Findings appear in the diff when it's done.")
            }
        case let .failed(message):
            AIErrorView(message: message)
            runButton(title: "Try Again")
        case nil:
            if let review {
                StructuredText(markdown: review.summary)
                    .textSelection(.enabled)
                footer(for: review)
            } else {
                Text("Get a summary of this pull request and a list of issues worth a closer look.")
                runButton(title: "Run AI Review")
            }
        }
    }

    private func footer(for review: AIReview) -> some View {
        HStack(spacing: 12) {
            Text("\(review.author) · \(review.createdAt, format: .relative(presentation: .named))")
                .font(.caption)
            if let files = review.guidelineFiles, !files.isEmpty {
                Label("Followed \(files.formatted(.list(type: .and)))", systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .help("The review followed the repository's own instructions for AI tools")
            }
            if review.headSHA != pullRequest.headSHA {
                Label("New commits since this review", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Review Again") { aiReviews.start(for: pullRequest) }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Run a new review with \(AISetup.description(of: .review, settings: settings))")
        }
    }

    private func runButton(title: String) -> some View {
        HStack(spacing: 10) {
            Button(title, systemImage: "sparkles") { aiReviews.start(for: pullRequest) }
                .buttonStyle(.glassProminent)
            Text("Uses \(AISetup.description(of: .review, settings: settings))")
                .font(.caption)
        }
    }
}

private struct FindingsSection: View {
    let findings: [ReviewFinding]
    let workspace: ReviewWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Findings (\(findings.count))")
                .font(.title3.weight(.semibold))
            ForEach(findings.sorted { $0.severity < $1.severity }) { finding in
                FindingRow(finding: finding) { workspace.reveal(finding) }
            }
        }
    }
}

/// Findings the latest commits fixed, collapsed by default.
private struct AddressedFindingsSection: View {
    let findings: [ReviewFinding]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(findings) { finding in
                    Label {
                        Text("\(finding.title) · \((finding.filePath as NSString).lastPathComponent)")
                            .strikethrough()
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Addressed by New Commits (\(findings.count))")
                .font(.title3.weight(.semibold))
        }
    }
}

/// One finding; clicking it opens the file at its line.
private struct FindingRow: View {
    let finding: ReviewFinding
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SeverityBadge(severity: finding.severity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.title)
                        .font(.headline)
                    Text("\((finding.filePath as NSString).lastPathComponent) · \(describeLines(finding.lines, on: finding.side))")
                        .font(.caption.monospaced())
                    InlineText(markdown: finding.body)
                        .font(.callout)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.opacity(isHovered ? 0.9 : 0.5), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open \(finding.filePath)")
    }
}

/// "3 new commits since your review yesterday", with a way to see only those changes.
private struct SinceLastReviewBanner: View {
    let workspace: ReviewWorkspace
    let sinceLastReview: SinceLastReview

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
            VStack(alignment: .leading, spacing: 4) {
                Text("\(sinceLastReview.commitCount) new \(sinceLastReview.commitCount == 1 ? "commit" : "commits") since your review \(sinceLastReview.reviewedAt.formatted(.relative(presentation: .named)))")
                    .font(.headline)
                Text("\(sinceLastReview.files.count) \(sinceLastReview.files.count == 1 ? "file" : "files") changed")
                    .font(.callout)
                if sinceLastReview.isRebased {
                    Label("The branch was rebased or force-pushed, so these changes may include work from \(workspace.pullRequest?.baseBranch ?? "the base branch").",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(workspace.showsChangesSinceLastReview ? "Show All Changes" : "Review These Changes") {
                workspace.setShowsChangesSinceLastReview(!workspace.showsChangesSinceLastReview)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.blue.opacity(0.12)), in: .rect(cornerRadius: 16))
    }
}

/// Does the change do what its description and linked issues ask for?
private struct SpecCheckSection: View {
    let specCheck: ReviewReport.SpecCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Does It Do What It Says?")
                .font(.title3.weight(.semibold))
            if specCheck.tooVagueToCheck == true || specCheck.goals.isEmpty {
                Label("The description is too thin to check the change against.", systemImage: "questionmark.circle")
            }
            ForEach(specCheck.goals, id: \.goal) { goal in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: symbol(for: goal.status))
                        .foregroundStyle(color(for: goal.status))
                        .help(goal.status.rawValue.capitalized)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.goal)
                            .font(.headline)
                        InlineText(markdown: goal.note)
                            .font(.callout)
                    }
                }
            }
            if !specCheck.unrequested.isEmpty {
                Text("Not asked for")
                    .font(.headline)
                    .padding(.top, 4)
                ForEach(specCheck.unrequested, id: \.self) { change in
                    Label {
                        InlineText(markdown: change)
                    } icon: {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.purple)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func symbol(for status: ReviewReport.SpecCheck.Status) -> String {
        switch status {
        case .addressed: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .missing: "xmark.circle.fill"
        }
    }

    private func color(for status: ReviewReport.SpecCheck.Status) -> Color {
        switch status {
        case .addressed: .green
        case .partial: .orange
        case .missing: .red
        }
    }
}

/// Things only the author can answer. Asking one opens a comment on its line.
private struct QuestionsSection: View {
    let questions: [AuthorQuestion]
    let workspace: ReviewWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Questions for the Author")
                .font(.title3.weight(.semibold))
            ForEach(questions) { question in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "questionmark.bubble")
                    VStack(alignment: .leading, spacing: 2) {
                        InlineText(markdown: question.question)
                        Text("\((question.filePath as NSString).lastPathComponent) · line \(question.lineIndex + 1)")
                            .font(.caption.monospaced())
                    }
                    Spacer(minLength: 8)
                    Button("Ask") { workspace.ask(question) }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .help("Open a comment with this question on its line")
                }
            }
        }
    }
}

/// Conversations already on the pull request; open ones first.
private struct ConversationsSection: View {
    let workspace: ReviewWorkspace

    var body: some View {
        let open = workspace.threads.filter { !$0.isResolved }
        VStack(alignment: .leading, spacing: 10) {
            Text("Conversations (\(open.count) open, \(workspace.threads.count - open.count) resolved)")
                .font(.title3.weight(.semibold))
            ForEach(open) { thread in
                ConversationRow(thread: thread) { workspace.reveal(thread) }
            }
            if !workspace.unresolvedThreads.isEmpty {
                Text("⌥⌘] jumps to the next open conversation.")
                    .font(.caption)
            }
        }
    }
}

private struct ConversationRow: View {
    let thread: GitHubReviewThread
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(thread.allComments.first?.author?.login ?? "Someone") on \((thread.path as NSString).lastPathComponent)\(thread.line.map { ", line \($0)" } ?? "")")
                        .font(.headline)
                    InlineText(markdown: thread.allComments.last?.body ?? "")
                        .font(.callout)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if thread.lineIndex == nil {
                    Text("Outdated")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.opacity(isHovered ? 0.9 : 0.5), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(thread.lineIndex == nil)
        .help(thread.lineIndex == nil ? "The lines this was on have changed" : "Open \(thread.path)")
    }
}

private struct DescriptionSection: View {
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Description")
                .font(.title3.weight(.semibold))
            if description.isEmpty {
                Text("No description provided.")
            } else {
                StructuredText(markdown: description)
                    .textSelection(.enabled)
            }
        }
    }
}

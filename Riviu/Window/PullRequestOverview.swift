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
                AISummaryCard(pullRequest: pullRequest, aiReviews: aiReviews)
                if !workspace.findings.isEmpty {
                    FindingsSection(findings: workspace.findings, workspace: workspace)
                }
                DescriptionSection(description: pullRequest.summary)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct OverviewHeader: View {
    let pullRequest: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pullRequest.reference.isDemo ? "Demo #\(pullRequest.number)" : pullRequest.reference.id)
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

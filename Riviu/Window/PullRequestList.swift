import RiviuGitHub
import SwiftUI

/// Pull requests from GitHub, filtered by involvement, state, repository and search text.
struct PullRequestList: View {
    @Bindable var inbox: PullRequestInbox
    let account: GitHubAccount
    let workspace: ReviewWorkspace
    let aiReviews: AIReviewStore
    let onOpen: (PullRequestReference) -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            switch account.status {
            case .checking:
                ProgressView("Connecting to GitHub…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedIn:
                filters
                results
            case .signedOut:
                signedOut
            }
        }
        .onAppear {
            searchText = inbox.query.text
            if account.isSignedIn && inbox.pullRequests.isEmpty { inbox.refresh() }
        }
        .onChange(of: account.isSignedIn) { _, isSignedIn in
            if isSignedIn { inbox.refresh() }
        }
    }

    // MARK: - Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Show", selection: $inbox.query.involvement) {
                    ForEach(PullRequestQuery.Involvement.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Picker("Repository", selection: $inbox.query.repository) {
                    Text("All repositories").tag(String?.none)
                    Divider()
                    ForEach(inbox.knownRepositories, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Spacer(minLength: 0)
            }
            .labelsHidden()
            Picker("State", selection: $inbox.query.state) {
                ForEach(PullRequestQuery.State.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("Search, e.g. label:bug", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { inbox.query.text = searchText }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if let errorMessage = inbox.errorMessage, inbox.pullRequests.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Pull Requests", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { inbox.refresh() }
            }
            .frame(maxHeight: .infinity)
        } else if inbox.pullRequests.isEmpty && !inbox.isLoading {
            ContentUnavailableView("No Pull Requests", systemImage: "tray",
                                   description: Text("Nothing matches these filters."))
                .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(inbox.pullRequests) { summary in
                    let reference = PullRequestReference(repository: summary.repository, number: summary.number)
                    Button { onOpen(reference) } label: {
                        PullRequestRow(summary: summary, reference: reference, isOpen: workspace.pullRequest?.reference == reference,
                                       aiReviews: aiReviews)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .overlay(alignment: .top) {
                if inbox.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(6)
                }
            }
        }
    }

    // MARK: - Signed out

    private var signedOut: some View {
        List {
            Section {
                GitHubSignInOptions(account: account)
                    .padding(.vertical, 6)
            } header: {
                Text("Connect GitHub")
            }
            Section("Demo pull requests") {
                ForEach(DemoPullRequests.all) { pullRequest in
                    Button { onOpen(pullRequest.reference) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pullRequest.title)
                                .lineLimit(2)
                            Text("#\(pullRequest.number) · \(pullRequest.author)")
                                .font(.caption)
                            AIReviewStatusLabel(reference: pullRequest.reference, aiReviews: aiReviews)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct PullRequestRow: View {
    let summary: GitHubPullRequestSummary
    let reference: PullRequestReference
    let isOpen: Bool
    let aiReviews: AIReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                stateIcon
                Text(summary.title)
                    .font(.body.weight(isOpen ? .semibold : .regular))
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text("\(summary.repository) #\(summary.number)")
                Text("·")
                Text(summary.user.login)
                Spacer(minLength: 4)
                if summary.comments > 0 {
                    Label("\(summary.comments)", systemImage: "bubble.left")
                }
                Text(summary.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
            }
            .font(.caption)
            .lineLimit(1)
            AIReviewStatusLabel(reference: reference, aiReviews: aiReviews)
            if !summary.labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(summary.labels.prefix(3), id: \.name) { label in
                        Text(label.name)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(hex: label.color).opacity(0.25), in: .capsule)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 6)
        .contentShape(.rect)
    }

    private var stateIcon: some View {
        let (symbol, color): (String, Color) = if summary.isMerged {
            ("arrow.triangle.merge", .purple)
        } else if summary.state == "closed" {
            ("xmark.circle", .red)
        } else if summary.isDraft {
            ("circle.dashed", .gray)
        } else {
            ("arrow.triangle.pull", .green)
        }
        return Image(systemName: symbol)
            .foregroundStyle(color)
            .help(summary.isDraft ? "Draft" : summary.state.capitalized)
    }
}

extension Color {
    /// A color from a hex string like "d73a4a", as GitHub uses for labels.
    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0x808080
        self.init(nsColor: NSColor(hex: value))
    }
}

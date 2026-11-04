import RiviuGitHub
import SwiftUI

/// The menu bar window: pull requests waiting for your review and where each one's AI summary is at.
struct MenuBarPanel: View {
    let watcher: ReviewRequestWatcher
    let account: GitHubAccount
    let aiReviews: AIReviewStore
    let tabs: ReviewTabs
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxHeight: 420)
            Divider()
            footer
        }
        .frame(width: 360)
        .onAppear { tabs.remember(openWindow) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Requests")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
            }
            Spacer()
            Button { Task { await watcher.checkNow() } } label: {
                if watcher.isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Check Now", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderless)
            .disabled(!account.isSignedIn || watcher.isChecking)
            .help("Check for new review requests")
        }
        .padding(12)
    }

    private var statusText: String {
        guard account.isSignedIn else { return "Not signed in to GitHub" }
        guard let lastChecked = watcher.lastChecked else { return "Checking…" }
        let checked = "Checked \(lastChecked.formatted(.relative(presentation: .named)))"
        switch watcher.requests.count {
        case 0: return checked
        case 1: return "1 waiting  \(checked)"
        case let count: return "\(count) waiting  \(checked)"
        }
    }

    @ViewBuilder
    private var content: some View {
        if !account.isSignedIn {
            Text("Sign in to GitHub in Riviu to see pull requests waiting for your review.")
                .padding(12)
        } else if watcher.requests.isEmpty {
            Label("Nothing waiting for your review.", systemImage: "checkmark.circle")
                .padding(12)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(watcher.requests) { summary in
                        RequestRow(summary: summary, aiReviews: aiReviews) { open(summary) }
                    }
                }
                .padding(6)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Riviu") { tabs.show() }
            Spacer()
            SettingsLink { Text("Settings…") }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    private func open(_ summary: GitHubPullRequestSummary) {
        tabs.open(PullRequestReference(repository: summary.repository, number: summary.number))
    }
}

private struct RequestRow: View {
    let summary: GitHubPullRequestSummary
    let aiReviews: AIReviewStore
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(summary.repository) #\(String(summary.number))  \(summary.user.login)")
                    .font(.caption)
                    .lineLimit(1)
                AIReviewStatusLabel(reference: PullRequestReference(repository: summary.repository, number: summary.number),
                                    aiReviews: aiReviews)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(isHovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

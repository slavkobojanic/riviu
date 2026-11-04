import AppKit
import RiviuGitHub
import SwiftUI

/// Pull requests from GitHub, filtered by involvement, state, repository and search text.
struct PullRequestList: View {
    @Bindable var inbox: PullRequestInbox
    let account: GitHubAccount
    let workspace: ReviewWorkspace
    let aiReviews: AIReviewStore
    let onOpen: (PullRequestReference) -> Void
    @Environment(ReviewTabs.self) private var tabs

    @State private var searchText = ""
    /// The highlighted row. It follows the open pull request, and the arrow keys move it.
    @State private var selection: PullRequestReference?

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
                .frame(maxWidth: .infinity)
                Picker("Repository", selection: $inbox.query.repository) {
                    Text("All repositories").tag(String?.none)
                    Divider()
                    ForEach(inbox.knownRepositories, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .frame(maxWidth: .infinity)
            }
            .labelsHidden()
            Picker("State", selection: $inbox.query.state) {
                ForEach(PullRequestQuery.State.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            SearchField(text: $searchText, prompt: "Search, e.g. label:bug") {
                inbox.query.text = searchText
            }
        }
        // Searches once typing pauses. Clearing the field goes back to the full list.
        .task(id: searchText) {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return // the text changed again
            }
            inbox.query.text = searchText
        }
        // Menus and segments stretch to fill their frame instead of sitting centered in it.
        .buttonSizing(.flexible)
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
            List(selection: Binding(get: { selection }, set: select)) {
                ForEach(inbox.pullRequests) { summary in
                    let reference = PullRequestReference(repository: summary.repository, number: summary.number)
                    PullRequestRow(summary: summary, reference: reference, aiReviews: aiReviews)
                        .tag(reference)
                }
            }
            .contextMenu(forSelectionType: PullRequestReference.self) { references in
                if let reference = references.first {
                    Button("Open") { onOpen(reference) }
                    Button("Open in New Tab") { tabs.open(reference) }
                }
            } primaryAction: { references in
                // Return or a double-click.
                if let reference = references.first { onOpen(reference) }
            }
            .onChange(of: openReference, initial: true) { _, reference in
                selection = reference
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

    /// The pull request open in this tab, or loading.
    private var openReference: PullRequestReference? {
        workspace.pullRequest?.reference ?? workspace.loadingReference
    }

    /// A click opens the pull request, and ⌘-click opens it in a new tab, like a link in Safari.
    /// The arrow keys only move the selection, so you can look down the list; Return opens it.
    private func select(_ reference: PullRequestReference?) {
        let event = NSApp.currentEvent
        if event?.type == .keyDown {
            selection = reference
            return
        }
        // ⌘-clicking the selected row asks to deselect it, which gives no row to open.
        guard let reference else { return }
        if event?.modifierFlags.contains(.command) == true {
            tabs.open(reference)
        } else {
            selection = reference
            onOpen(reference)
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
        }
        .listStyle(.sidebar)
    }
}

/// One pull request, laid out like a message in Mail: the state symbol in its own column, the title with the time
/// beside it, then quieter details underneath.
private struct PullRequestRow: View {
    let summary: GitHubPullRequestSummary
    let reference: PullRequestReference
    let aiReviews: AIReviewStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            stateIcon
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(summary.title)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(summary.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                details
                AIReviewStatusLabel(reference: reference, aiReviews: aiReviews)
                if !summary.labels.isEmpty {
                    labels
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    /// "wedded #80  slavkobojanic", and the number of comments.
    private var details: some View {
        HStack(spacing: 8) {
            Text("\(repositoryName) #\(String(summary.number))")
                .help(summary.repository)
            Text(summary.user.login)
            if summary.comments > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bubble.left")
                    Text("\(summary.comments)")
                }
                .help(summary.comments == 1 ? "1 comment" : "\(summary.comments) comments")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// A coloured dot and the name, like Finder's tags.
    private var labels: some View {
        HStack(spacing: 10) {
            ForEach(summary.labels.prefix(3), id: \.name) { label in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: label.color))
                        .frame(width: 7, height: 7)
                    Text(label.name)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// "wedded" from "slavkobojanic/wedded". The owner is the same on most rows, so it's left out.
    private var repositoryName: String {
        summary.repository.split(separator: "/").last.map(String.init) ?? summary.repository
    }

    private var stateIcon: some View {
        let (symbol, color): (String, Color) = if summary.isMerged {
            ("arrow.triangle.merge", .purple)
        } else if summary.state == "closed" {
            ("xmark.circle", .statusRed)
        } else if summary.isDraft {
            ("circle.dashed", .gray)
        } else {
            ("arrow.triangle.pull", .statusGreen)
        }
        let name = summary.isMerged ? "Merged" : summary.isDraft ? "Draft" : summary.state.capitalized
        return Image(systemName: symbol)
            .foregroundStyle(color)
            .help(name)
            .accessibilityLabel(name)
    }
}

/// AppKit's search field, for the magnifying glass and clear button that SwiftUI's text field doesn't have.
/// `onSubmit` runs on Return and when the clear button is clicked.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        // Only Return and the clear button send the action; typing is handled by `controlTextDidChange`.
        field.sendsWholeSearchString = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField

        init(parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        @objc func submit(_ sender: NSSearchField) {
            parent.text = sender.stringValue
            parent.onSubmit()
        }
    }
}

extension Color {
    /// A color from a hex string like "d73a4a", as GitHub uses for labels.
    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0x808080
        self.init(nsColor: NSColor(hex: value))
    }
}

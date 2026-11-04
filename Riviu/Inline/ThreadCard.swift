import RiviuGitHub
import RiviuMarkdown
import SwiftUI

/// A conversation already on the pull request, with a reply field and Resolve. Resolved ones start collapsed.
struct ThreadCard: View {
    let thread: GitHubReviewThread
    let workspace: ReviewWorkspace

    @State private var isExpanded: Bool
    @State private var reply = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var isReplyFocused: Bool

    init(thread: GitHubReviewThread, workspace: ReviewWorkspace) {
        self.thread = thread
        self.workspace = workspace
        _isExpanded = State(initialValue: !thread.isResolved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isExpanded {
                ForEach(thread.allComments) { comment in
                    CommentRow(comment: comment)
                }
                replyField
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.statusRed)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(14)
        .cardBackground(cornerRadius: 16)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text(title)
                        .font(.headline)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if thread.isResolved {
                Label("Resolved", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.statusGreen)
            } else if thread.isOutdated {
                Text("Outdated")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.statusOrange)
            }
            Spacer()
            Button(thread.isResolved ? "Unresolve" : "Resolve", systemImage: thread.isResolved ? "arrow.uturn.backward" : "checkmark") {
                run { try await workspace.setResolved(!thread.isResolved, thread: thread) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
        }
    }

    private var title: String {
        let starter = thread.allComments.first?.author?.login ?? "Someone"
        let replies = thread.allComments.count - 1
        return replies > 0 ? "\(starter)  \(replies) \(replies == 1 ? "reply" : "replies")" : starter
    }

    private var replyField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply…", text: $reply, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($isReplyFocused)
                .padding(8)
                .textFieldBackground(isFocused: isReplyFocused)
                .onSubmit(sendReply)
            Button("Reply", action: sendReply)
                .buttonStyle(.borderedProminent)
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
        }
    }

    private func sendReply() {
        let body = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        run {
            try await workspace.reply(to: thread, body: body)
            reply = ""
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

private struct CommentRow: View {
    let comment: GitHubReviewThread.Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.author?.login ?? "ghost")
                    .font(.subheadline.weight(.semibold))
                Text(comment.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
            }
            StructuredText(markdown: comment.body)
                .textual.textSelection(.enabled)
        }
    }
}

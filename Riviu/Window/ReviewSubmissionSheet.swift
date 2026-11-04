import RiviuGitHub
import RiviuMarkdown
import SwiftUI

/// Sends the review to GitHub: a summary, the verdict, and every pending comment.
struct ReviewSubmissionSheet: View {
    let workspace: ReviewWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var event: GitHubReviewSubmission.Event
    @State private var summary = ""
    @State private var errorMessage: String?

    init(workspace: ReviewWorkspace, initialEvent: GitHubReviewSubmission.Event) {
        self.workspace = workspace
        _event = State(initialValue: initialEvent)
    }

    var body: some View {
        Form {
            Section("Summary") {
                TextEditor(text: $summary)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                if !summary.isEmpty {
                    StructuredText(markdown: summary)
                }
            }
            Section {
                Picker("Verdict", selection: $event) {
                    Text("Comment").tag(GitHubReviewSubmission.Event.comment)
                    Text("Approve").tag(GitHubReviewSubmission.Event.approve)
                    Text("Request changes").tag(GitHubReviewSubmission.Event.requestChanges)
                }
                .pickerStyle(.radioGroup)
            }
            Section("Comments (\(workspace.pendingComments.count))") {
                if workspace.pendingComments.isEmpty {
                    Text("No pending comments.")
                }
                ForEach(workspace.pendingComments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(comment.filePath)  \(comment.lineLabel)")
                            .font(.caption.weight(.semibold))
                        Text(comment.body)
                            .lineLimit(2)
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.statusRed)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Submit Review", action: submit)
                    .disabled(!canSubmit)
            }
        }
    }

    /// GitHub needs a summary to request changes or to leave a review with no line comments.
    private var canSubmit: Bool {
        if workspace.isSubmittingReview { return false }
        let hasSummary = !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch event {
        case .approve: return true
        case .requestChanges: return hasSummary
        case .comment: return hasSummary || !workspace.pendingComments.isEmpty
        }
    }

    private func submit() {
        Task {
            do {
                try await workspace.submitReview(event: event, body: summary)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

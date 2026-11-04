import RiviuMarkdown
import SwiftUI

/// A saved comment, rendered as Markdown.
struct CommentCard: View {
    let comment: ReviewComment
    let workspace: ReviewWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                Text("You")
                    .font(.headline)
                Text("Pending · \(comment.lineLabel)")
                    .font(.subheadline)
                Spacer()
                editButtons
            }
            StructuredText(markdown: comment.body)
                .textual.textSelection(.enabled)
        }
        .foregroundStyle(.primary)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var editButtons: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 2) {
                Button("Edit", systemImage: "pencil") { workspace.editComment(comment.id) }
                Button("Delete", systemImage: "trash") { workspace.deleteComment(comment.id) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
        }
    }
}

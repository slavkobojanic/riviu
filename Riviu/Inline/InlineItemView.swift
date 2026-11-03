import RiviuDiff
import SwiftUI

/// Hosts a finding or comment between diff lines and reports how tall it wants to be.
struct InlineItemView: View {
    let id: AttachmentID
    let workspace: ReviewWorkspace
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        content
            .padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch workspace.inlineItem(for: id) {
        case let .finding(finding):
            FindingCard(finding: finding, workspace: workspace)
        case let .comment(comment) where comment.isEditing:
            CommentComposer(comment: comment, workspace: workspace)
        case let .comment(comment):
            CommentCard(comment: comment, workspace: workspace)
        case nil:
            EmptyView()
        }
    }
}

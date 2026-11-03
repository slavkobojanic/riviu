import SwiftUI

/// Where a pull request's AI review is at: "Summary queued", "Generating summary…", or "High risk · 3 findings".
struct AIReviewStatusLabel: View {
    let reference: PullRequestReference
    let aiReviews: AIReviewStore
    /// Shown when there's no review and none is coming. nil shows nothing.
    var placeholder: String?

    var body: some View {
        Group {
            switch aiReviews.activity(for: reference) {
            case .queued:
                Label("Summary queued", systemImage: "clock")
            case .reviewing:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Generating summary…")
                }
            case .failed:
                Label("Summary failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case nil:
                if let review = aiReviews.review(for: reference) {
                    HStack(spacing: 6) {
                        SeverityBadge(severity: review.risk, label: "\(review.risk.rawValue) risk")
                        Text(review.findings.count == 1 ? "1 finding" : "\(review.findings.count) findings")
                    }
                } else if let placeholder {
                    Label(placeholder, systemImage: "sparkles")
                }
            }
        }
        .font(.caption)
    }
}

import SwiftUI

/// Where a pull request's AI review is at: "Summary queued", "Generating summary…", or "High risk  3 findings".
struct AIReviewStatusLabel: View {
    let reference: PullRequestReference
    let aiReviews: AIReviewStore

    var body: some View {
        Group {
            switch aiReviews.activity(for: reference) {
            case .queued:
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("Summary queued")
                }
            case .reviewing:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Generating summary…")
                }
            case .failed:
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.statusRed)
                    Text("Summary failed")
                }
            case nil:
                if let review = aiReviews.review(for: reference) {
                    HStack(spacing: 8) {
                        SeverityLabel(severity: review.risk, label: "\(review.risk.rawValue) risk")
                        Text(review.findings.count == 1 ? "1 finding" : "\(review.findings.count) findings")
                    }
                }
            }
        }
        .font(.caption)
        // Quieter than the title it sits under. Symbols with their own colour keep it.
        .foregroundStyle(.secondary)
    }
}

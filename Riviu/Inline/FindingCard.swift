import RiviuMarkdown
import SwiftUI

struct FindingCard: View {
    let finding: ReviewFinding
    let workspace: ReviewWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.purple)
                Text(finding.title)
                    .font(.headline)
                Spacer()
                SeverityBadge(severity: finding.severity)
            }
            InlineText(markdown: finding.body)
                .font(.callout)
            HStack(spacing: 8) {
                Button("Add as Comment", systemImage: "text.bubble") { workspace.turnFindingIntoComment(finding) }
                Button("Dismiss", systemImage: "xmark") { workspace.dismissFinding(finding) }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .foregroundStyle(.primary)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct SeverityBadge: View {
    let severity: ReviewFinding.Severity
    /// Shown instead of the severity's name, like "High risk".
    var label: String?

    var body: some View {
        Text(label ?? severity.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.22), in: .capsule)
    }

    private var color: Color {
        switch severity {
        case .high: .red
        case .medium: .orange
        case .low: .blue
        }
    }
}

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
            if let suggestion = finding.suggestion {
                SuggestedFix(code: suggestion)
            }
            HStack(spacing: 8) {
                Button(finding.suggestion == nil ? "Add as Comment" : "Add Comment with Fix", systemImage: "text.bubble") {
                    workspace.turnFindingIntoComment(finding)
                }
                .help(finding.suggestion == nil ? "Turn this finding into a review comment"
                                                : "Turn this finding into a review comment the author can commit with one click")
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

/// The replacement code the AI proposes, shown before it becomes a GitHub suggestion.
private struct SuggestedFix: View {
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Suggested fix", systemImage: "wand.and.sparkles")
                .font(.caption.weight(.semibold))
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.green.opacity(0.12), in: .rect(cornerRadius: 10))
        }
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

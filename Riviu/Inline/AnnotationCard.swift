import RiviuGitHub
import SwiftUI

/// A message a CI check left on a line, like a lint warning or a failed test.
struct AnnotationCard: View {
    let annotation: GitHubCheckAnnotation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                if let title = annotation.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                }
                Text(annotation.message)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Text("CI")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.22), in: .capsule)
        }
        .foregroundStyle(.primary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(color.opacity(0.12)), in: .rect(cornerRadius: 14))
    }

    private var symbol: String {
        switch annotation.annotationLevel {
        case "failure": "xmark.octagon.fill"
        case "warning": "exclamationmark.triangle.fill"
        default: "info.circle.fill"
        }
    }

    private var color: Color {
        switch annotation.annotationLevel {
        case "failure": .statusRed
        case "warning": .statusOrange
        default: .blue
        }
    }
}

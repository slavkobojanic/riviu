import SwiftUI

/// The two buttons shown next to a hovered block or a selection.
struct GutterActions: View {
    var onExplain: () -> Void
    var onComment: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 2) {
                Button("Explain with AI", systemImage: "sparkles", action: onExplain)
                Button("Comment", systemImage: "text.bubble", action: onComment)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
        }
        .padding(1)
    }
}

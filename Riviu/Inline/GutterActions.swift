import SwiftUI

/// The buttons shown next to a hovered block or a selection.
struct GutterActions: View {
    var onExplain: () -> Void
    var onHotPath: () -> Void
    var onComment: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 2) {
                Button("Explain with AI", systemImage: "sparkles", action: onExplain)
                    .help("Explain with AI")
                Button("Hot Path", systemImage: "point.3.connected.trianglepath.dotted", action: onHotPath)
                    .help("Show what calls this and what it calls (⌥H)")
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

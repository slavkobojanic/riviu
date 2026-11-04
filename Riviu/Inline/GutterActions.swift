import AppKit
import SwiftUI

/// The buttons shown next to a hovered block or a selection. Resting on a button for a second shows what it does.
///
/// The tooltip is drawn here rather than with `.help`, because these buttons sit in a hosting view that moves with
/// the mouse and lets clicks through around them; it's styled to look like the system's tooltip.
struct GutterActions: View {
    /// Room above and to the right of the buttons for a tooltip, which can be wider than the buttons.
    static let tooltipRoom = CGSize(width: 320, height: 30)

    var onExplain: () -> Void
    var onHotPath: () -> Void
    var onComment: () -> Void

    @State private var hoveredButton: String?
    @State private var tooltipButton: String?

    var body: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 2) {
                button("Explain with AI", systemImage: "sparkles", tooltip: "Explain with AI", action: onExplain)
                button("Hot Path", systemImage: "point.3.connected.trianglepath.dotted",
                       tooltip: "Show what calls this and what it calls (⌥H)", action: onHotPath)
                button("Comment", systemImage: "text.bubble", tooltip: "Comment on these lines", action: onComment)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
        }
        .padding(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .task(id: hoveredButton) {
            tooltipButton = nil
            guard hoveredButton != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled {
                tooltipButton = hoveredButton
            }
        }
    }

    private func button(_ title: String, systemImage: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage) {
            hoveredButton = nil
            action()
        }
        .accessibilityHint(tooltip)
        .onHover { isHovering in
            if isHovering {
                hoveredButton = title
            } else if hoveredButton == title {
                hoveredButton = nil
            }
        }
        .overlay(alignment: .topLeading) {
            if tooltipButton == title {
                Text(tooltip)
                    .font(Font(NSFont.toolTipsFont(ofSize: 0)))
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator, lineWidth: 0.5))
                    .offset(y: -24)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Hosts the gutter buttons with room around them for a tooltip. Only the buttons take clicks;
/// the rest lets the mouse through to the code underneath.
final class GutterActionsHostingView: NSHostingView<GutterActions> {
    /// The size of the buttons alone, without the tooltip room.
    var buttonsSize: CGSize = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let buttonsY = isFlipped ? bounds.height - buttonsSize.height : 0
        let buttons = CGRect(x: 0, y: buttonsY, width: buttonsSize.width, height: buttonsSize.height)
        return buttons.contains(local) ? super.hitTest(point) : nil
    }
}

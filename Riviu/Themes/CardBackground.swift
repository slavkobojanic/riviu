import SwiftUI

/// The background of a card that sits in the content, like an AI finding in the diff or the summary on the overview.
/// It's opaque, not Liquid Glass: Apple keeps glass for controls and bars that float above the content.
struct CardBackground: ViewModifier {
    /// A colour mixed in lightly, like orange for a warning.
    var tint: Color?
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .background {
                shape.fill(Color(nsColor: .controlBackgroundColor))
                if let tint {
                    shape.fill(tint.opacity(0.1))
                }
            }
            .overlay {
                shape.strokeBorder(.separator)
            }
    }
}

extension View {
    /// An opaque card background with a hairline border. See `CardBackground`.
    func cardBackground(tint: Color? = nil, cornerRadius: CGFloat = 14) -> some View {
        modifier(CardBackground(tint: tint, cornerRadius: cornerRadius))
    }
}

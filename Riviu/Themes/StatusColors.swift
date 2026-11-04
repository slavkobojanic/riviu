import AppKit
import SwiftUI

/// Green, red and orange dark enough to read as text on a light background, and bright enough on a dark one.
/// The system colors are tuned for fills and icons, so they're too faint for words like "Checks passed".
/// The values are GitHub's, which are checked for contrast.
extension ShapeStyle where Self == Color {
    static var statusGreen: Color { adaptive(light: 0x1A7F37, dark: 0x3FB950) }
    static var statusRed: Color { adaptive(light: 0xCF222E, dark: 0xF85149) }
    static var statusOrange: Color { adaptive(light: 0x9A6700, dark: 0xD29922) }

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

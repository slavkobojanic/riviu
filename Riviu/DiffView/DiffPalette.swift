import AppKit

/// The colors the diff view draws with, worked out once per theme.
struct DiffPalette {
    let background: CGColor
    let text: CGColor
    let gutter: CGColor
    let filler: CGColor
    let lineNumber: CGColor
    let lineNumberEmphasized: CGColor
    let separator: CGColor
    let collapsedRow: CGColor
    let selection: CGColor
    let selectionGutter: CGColor
    let blockText: CGColor
    let blockGutter: CGColor
    let accent: CGColor
    let findMatch: CGColor
    let currentFindMatch: CGColor

    let addedLine: CGColor
    let addedGutter: CGColor
    let addedWord: CGColor
    let addedMarker: CGColor
    let removedLine: CGColor
    let removedGutter: CGColor
    let removedWord: CGColor
    let removedMarker: CGColor

    init(theme: EditorTheme, increaseContrast: Bool) {
        let dark = theme.isDark
        let boost: CGFloat = increaseContrast ? 1.6 : 1
        func tint(_ color: NSColor, dark darkAlpha: CGFloat, light lightAlpha: CGFloat) -> CGColor {
            color.withAlphaComponent((dark ? darkAlpha : lightAlpha) * boost).cgColor
        }

        background = theme.background.cgColor
        text = theme.foreground.cgColor
        gutter = tint(theme.foreground, dark: 0.04, light: 0.03)
        filler = tint(theme.foreground, dark: 0.06, light: 0.05)
        // Some themes' line-number colors are very faint; lift them until they're readable.
        lineNumber = ColorContrast.adjusted(theme.lineNumber, on: theme.background, toAtLeast: increaseContrast ? 4.5 : 3.2,
                                            toward: theme.foreground).cgColor
        lineNumberEmphasized = theme.foreground.cgColor
        separator = tint(theme.foreground, dark: 0.14, light: 0.14)
        collapsedRow = tint(theme.accent, dark: 0.10, light: 0.07)
        selection = theme.selection.cgColor
        selectionGutter = tint(theme.accent, dark: 0.22, light: 0.18)
        blockText = tint(theme.accent, dark: 0.08, light: 0.06)
        blockGutter = tint(theme.accent, dark: 0.18, light: 0.14)
        accent = theme.accent.cgColor
        findMatch = NSColor(hex: 0xFFD60A, alpha: dark ? 0.30 : 0.45).cgColor
        currentFindMatch = NSColor(hex: 0xFF9F0A, alpha: dark ? 0.65 : 0.70).cgColor

        let green = NSColor(hex: dark ? 0x3FB950 : 0x1A7F37)
        let red = NSColor(hex: dark ? 0xF85149 : 0xCF222E)
        addedLine = tint(green, dark: 0.15, light: 0.10)
        addedGutter = tint(green, dark: 0.24, light: 0.17)
        addedWord = tint(green, dark: 0.38, light: 0.26)
        addedMarker = green.cgColor
        removedLine = tint(red, dark: 0.15, light: 0.09)
        removedGutter = tint(red, dark: 0.24, light: 0.16)
        removedWord = tint(red, dark: 0.38, light: 0.25)
        removedMarker = red.cgColor
    }
}

/// WCAG contrast helpers.
enum ColorContrast {
    static func ratio(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let lighter = max(luminance(a), luminance(b))
        let darker = min(luminance(a), luminance(b))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Blends `color` toward `target` in small steps until it has enough contrast against `background`.
    static func adjusted(_ color: NSColor, on background: NSColor, toAtLeast minimum: CGFloat, toward target: NSColor) -> NSColor {
        var result = color
        var amount: CGFloat = 0
        while ratio(result, background) < minimum && amount < 1 {
            amount += 0.08
            result = color.blended(withFraction: amount, of: target) ?? target
        }
        return result
    }

    private static func luminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
}

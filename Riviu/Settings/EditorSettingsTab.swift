import AppKit
import SwiftUI

struct EditorSettingsTab: View {
    @Bindable var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private static let monospacedFamilies: [String] = NSFontManager.shared.availableFontFamilies.filter { family in
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13)?.isFixedPitch == true
    }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $settings.themeFamily) {
                    ForEach(EditorThemeFamily.allCases) { family in
                        ThemeSwatch(theme: family.theme(dark: colorScheme == .dark), title: family.variantNames)
                            .tag(family)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("Light or dark follows the appearance setting.")
                    .font(.caption)
            }

            Section("Font") {
                Picker("Font", selection: $settings.fontFamily) {
                    Text("SF Mono (System)").tag("")
                    Divider()
                    ForEach(Self.monospacedFamilies, id: \.self) { Text($0).tag($0) }
                }
                Stepper("Size: \(Int(settings.fontSize)) pt", value: $settings.fontSize, in: 9...28, step: 1)
                Picker("Line spacing", selection: $settings.lineSpacing) {
                    ForEach(LineSpacing.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Preview") {
                CodePreview(theme: settings.themeFamily.theme(dark: colorScheme == .dark), font: settings.editorFont,
                            lineSpacing: settings.lineSpacing)
            }
        }
        .formStyle(.grouped)
    }
}

/// A theme's name with a strip of its colors.
private struct ThemeSwatch: View {
    let theme: EditorTheme
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(["keyword", "string", "function", "type", "number"], id: \.self) { capture in
                    Rectangle()
                        .fill(Color(nsColor: theme.color(for: capture) ?? theme.foreground))
                        .frame(width: 10, height: 18)
                }
            }
            .padding(3)
            .background(Color(nsColor: theme.background), in: .rect(cornerRadius: 4))
            Text(title)
        }
    }
}

/// A few lines of code in the chosen theme and font.
private struct CodePreview: View {
    let theme: EditorTheme
    let font: NSFont
    let lineSpacing: LineSpacing

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing.extraHeight) {
            line([("func ", "keyword"), ("greet", "function"), ("(", nil), ("name", "variable.parameter"), (": ", nil), ("String", "type"), (") {", nil)])
            line([("    // Says hello", "comment")])
            line([("    let ", "keyword"), ("count", nil), (" = ", nil), ("42", "number")])
            line([("    print", "function"), ("(", nil), ("\"Hello, \\(name)\"", "string"), (")", nil)])
            line([("}", nil)])
        }
        .font(Font(font))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: theme.background), in: .rect(cornerRadius: 8))
    }

    private func line(_ parts: [(String, String?)]) -> Text {
        parts.reduce(Text("")) { text, part in
            let color = part.1.flatMap { theme.color(for: $0) } ?? theme.foreground
            return Text("\(text)\(Text(part.0).foregroundStyle(Color(nsColor: color)))")
        }
    }
}

import AppKit
import RiviuAI
import RiviuDiff
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum LineSpacing: String, CaseIterable, Identifiable {
    case compact, standard, relaxed

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Points added to the font's natural line height.
    var extraHeight: CGFloat {
        switch self {
        case .compact: 5
        case .standard: 9
        case .relaxed: 13
        }
    }
}

enum AIProviderKind: String, CaseIterable, Identifiable {
    case claudeCode, codex, cursor, anthropicAPI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .anthropicAPI: "Claude API (API key)"
        }
    }

    /// The CLI behind this provider, or nil for the API.
    var commandLineTool: CommandLineTool? {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .cursor: .cursor
        case .anthropicAPI: nil
        }
    }
}

/// Everything the user can configure, saved to UserDefaults as it changes.
/// The API key is not stored here; it lives in the keychain (see `AISetup`).
@Observable
final class AppSettings {
    var appearance: AppAppearance { didSet { save(appearance.rawValue, for: "appearance") } }
    var themeFamily: EditorThemeFamily { didSet { save(themeFamily.rawValue, for: "themeFamily") } }
    /// A font family name; empty means the system monospaced font (SF Mono).
    var fontFamily: String { didSet { save(fontFamily, for: "fontFamily") } }
    var fontSize: Double { didSet { save(fontSize, for: "fontSize") } }
    var lineSpacing: LineSpacing { didSet { save(lineSpacing.rawValue, for: "lineSpacing") } }

    var diffLayout: DiffLayout { didSet { save(diffLayout.rawValue, for: "diffLayout") } }
    var contextLines: Int { didSet { save(contextLines, for: "contextLines") } }
    var highlightsWordChanges: Bool { didSet { save(highlightsWordChanges, for: "highlightsWordChanges") } }
    var showsChatPanel: Bool { didSet { save(showsChatPanel, for: "showsChatPanel") } }

    var aiProvider: AIProviderKind { didSet { save(aiProvider.rawValue, for: "aiProvider") } }
    var anthropicModel: String { didSet { save(anthropicModel, for: "anthropicModel") } }
    /// Empty means "let the CLI choose".
    var claudeCodeModel: String { didSet { save(claudeCodeModel, for: "claudeCodeModel") } }
    var codexModel: String { didSet { save(codexModel, for: "codexModel") } }
    var cursorModel: String { didSet { save(cursorModel, for: "cursorModel") } }
    /// Empty means "find it on the PATH".
    var claudeCodePath: String { didSet { save(claudeCodePath, for: "claudeCodePath") } }
    var codexPath: String { didSet { save(codexPath, for: "codexPath") } }
    var cursorPath: String { didSet { save(cursorPath, for: "cursorPath") } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        themeFamily = EditorThemeFamily(rawValue: defaults.string(forKey: "themeFamily") ?? "") ?? .one
        fontFamily = defaults.string(forKey: "fontFamily") ?? ""
        fontSize = defaults.object(forKey: "fontSize") as? Double ?? 13
        lineSpacing = LineSpacing(rawValue: defaults.string(forKey: "lineSpacing") ?? "") ?? .standard
        diffLayout = DiffLayout(rawValue: defaults.string(forKey: "diffLayout") ?? "") ?? .split
        contextLines = defaults.object(forKey: "contextLines") as? Int ?? 3
        highlightsWordChanges = defaults.object(forKey: "highlightsWordChanges") as? Bool ?? true
        showsChatPanel = defaults.object(forKey: "showsChatPanel") as? Bool ?? true
        aiProvider = AIProviderKind(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .claudeCode
        anthropicModel = defaults.string(forKey: "anthropicModel") ?? AnthropicAPIProvider.defaultModel
        claudeCodeModel = defaults.string(forKey: "claudeCodeModel") ?? ""
        codexModel = defaults.string(forKey: "codexModel") ?? ""
        cursorModel = defaults.string(forKey: "cursorModel") ?? ""
        claudeCodePath = defaults.string(forKey: "claudeCodePath") ?? ""
        codexPath = defaults.string(forKey: "codexPath") ?? ""
        cursorPath = defaults.string(forKey: "cursorPath") ?? ""
    }

    var editorFont: NSFont {
        let size = CGFloat(fontSize)
        let regularWeight = 5
        let chosen = NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: regularWeight, size: size)
        return chosen ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func model(for tool: CommandLineTool) -> String {
        switch tool {
        case .claudeCode: claudeCodeModel
        case .codex: codexModel
        case .cursor: cursorModel
        }
    }

    func customPath(for tool: CommandLineTool) -> String {
        switch tool {
        case .claudeCode: claudeCodePath
        case .codex: codexPath
        case .cursor: cursorPath
        }
    }

    func setModel(_ model: String, for tool: CommandLineTool) {
        switch tool {
        case .claudeCode: claudeCodeModel = model
        case .codex: codexModel = model
        case .cursor: cursorModel = model
        }
    }

    func setCustomPath(_ path: String, for tool: CommandLineTool) {
        switch tool {
        case .claudeCode: claudeCodePath = path
        case .codex: codexPath = path
        case .cursor: cursorPath = path
        }
    }

    private func save(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
    }
}

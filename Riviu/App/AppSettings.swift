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

    /// Models to suggest in Settings. CLIs also accept any model name their account allows.
    var suggestedModels: [String] {
        switch self {
        case .claudeCode: ["opus", "sonnet", "haiku"]
        case .anthropicAPI: AnthropicAPIProvider.models
        case .codex, .cursor: []
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

/// The jobs AI does in Riviu. Each can use its own provider, model and instructions.
enum AITask: String, CaseIterable, Identifiable {
    case review, chat, explain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: "AI Review"
        case .chat: "Chat"
        case .explain: "Explain"
        }
    }
}

enum ExplanationLength: String, CaseIterable, Identifiable {
    case brief, standard, detailed

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Added to the Explain instructions.
    var instruction: String {
        switch self {
        case .brief: "Keep the whole answer under 80 words."
        case .standard: "Keep the whole answer under 200 words."
        case .detailed: "Be thorough, but keep the whole answer under 500 words."
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
    /// Keeps Riviu in the menu bar, still checking for review requests, after its window is closed.
    var keepsRunningInMenuBar: Bool { didSet { save(keepsRunningInMenuBar, for: "keepsRunningInMenuBar") } }

    var reviewProvider: AIProviderKind { didSet { save(reviewProvider.rawValue, for: "reviewProvider") } }
    var chatProvider: AIProviderKind { didSet { save(chatProvider.rawValue, for: "chatProvider") } }
    var explainProvider: AIProviderKind { didSet { save(explainProvider.rawValue, for: "explainProvider") } }
    /// Empty means the provider's default model.
    var reviewModel: String { didSet { save(reviewModel, for: "reviewModel") } }
    var chatModel: String { didSet { save(chatModel, for: "chatModel") } }
    var explainModel: String { didSet { save(explainModel, for: "explainModel") } }
    var reviewInstructions: String { didSet { save(reviewInstructions, for: "reviewInstructions") } }
    var chatInstructions: String { didSet { save(chatInstructions, for: "chatInstructions") } }
    var explainInstructions: String { didSet { save(explainInstructions, for: "explainInstructions") } }
    var explanationLength: ExplanationLength { didSet { save(explanationLength.rawValue, for: "explanationLength") } }
    /// Empty means "find it on the PATH".
    var claudeCodePath: String { didSet { save(claudeCodePath, for: "claudeCodePath") } }
    var codexPath: String { didSet { save(codexPath, for: "codexPath") } }
    var cursorPath: String { didSet { save(cursorPath, for: "cursorPath") } }

    var checksForReviewRequests: Bool { didSet { save(checksForReviewRequests, for: "checksForReviewRequests") } }
    var reviewRequestCheckMinutes: Int { didSet { save(reviewRequestCheckMinutes, for: "reviewRequestCheckMinutes") } }
    var notifiesAboutReviewRequests: Bool { didSet { save(notifiesAboutReviewRequests, for: "notifiesAboutReviewRequests") } }
    var reviewsNewRequestsWithAI: Bool { didSet { save(reviewsNewRequestsWithAI, for: "reviewsNewRequestsWithAI") } }

    /// Client ID of a GitHub OAuth App, which turns on "Sign in with GitHub" in the browser.
    var gitHubClientID: String { didSet { save(gitHubClientID, for: "gitHubClientID") } }

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
        keepsRunningInMenuBar = defaults.object(forKey: "keepsRunningInMenuBar") as? Bool ?? true
        reviewProvider = AIProviderKind(rawValue: defaults.string(forKey: "reviewProvider") ?? "") ?? .claudeCode
        chatProvider = AIProviderKind(rawValue: defaults.string(forKey: "chatProvider") ?? "") ?? .claudeCode
        explainProvider = AIProviderKind(rawValue: defaults.string(forKey: "explainProvider") ?? "") ?? .claudeCode
        reviewModel = defaults.string(forKey: "reviewModel") ?? ""
        chatModel = defaults.string(forKey: "chatModel") ?? ""
        explainModel = defaults.string(forKey: "explainModel") ?? ""
        reviewInstructions = defaults.string(forKey: "reviewInstructions") ?? ReviewPrompts.defaultInstructions(for: .review)
        chatInstructions = defaults.string(forKey: "chatInstructions") ?? ReviewPrompts.defaultInstructions(for: .chat)
        explainInstructions = defaults.string(forKey: "explainInstructions") ?? ReviewPrompts.defaultInstructions(for: .explain)
        explanationLength = ExplanationLength(rawValue: defaults.string(forKey: "explanationLength") ?? "") ?? .brief
        claudeCodePath = defaults.string(forKey: "claudeCodePath") ?? ""
        codexPath = defaults.string(forKey: "codexPath") ?? ""
        cursorPath = defaults.string(forKey: "cursorPath") ?? ""
        checksForReviewRequests = defaults.object(forKey: "checksForReviewRequests") as? Bool ?? true
        reviewRequestCheckMinutes = defaults.object(forKey: "reviewRequestCheckMinutes") as? Int ?? 5
        notifiesAboutReviewRequests = defaults.object(forKey: "notifiesAboutReviewRequests") as? Bool ?? true
        reviewsNewRequestsWithAI = defaults.object(forKey: "reviewsNewRequestsWithAI") as? Bool ?? true
        gitHubClientID = defaults.string(forKey: "gitHubClientID") ?? ""
    }

    var editorFont: NSFont {
        let size = CGFloat(fontSize)
        let regularWeight = 5
        let chosen = NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: regularWeight, size: size)
        return chosen ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func provider(for task: AITask) -> AIProviderKind {
        switch task {
        case .review: reviewProvider
        case .chat: chatProvider
        case .explain: explainProvider
        }
    }

    func setProvider(_ provider: AIProviderKind, for task: AITask) {
        switch task {
        case .review: reviewProvider = provider
        case .chat: chatProvider = provider
        case .explain: explainProvider = provider
        }
    }

    func model(for task: AITask) -> String {
        switch task {
        case .review: reviewModel
        case .chat: chatModel
        case .explain: explainModel
        }
    }

    func setModel(_ model: String, for task: AITask) {
        switch task {
        case .review: reviewModel = model
        case .chat: chatModel = model
        case .explain: explainModel = model
        }
    }

    func instructions(for task: AITask) -> String {
        switch task {
        case .review: reviewInstructions
        case .chat: chatInstructions
        case .explain: explainInstructions
        }
    }

    func setInstructions(_ instructions: String, for task: AITask) {
        switch task {
        case .review: reviewInstructions = instructions
        case .chat: chatInstructions = instructions
        case .explain: explainInstructions = instructions
        }
    }

    func customPath(for tool: CommandLineTool) -> String {
        switch tool {
        case .claudeCode: claudeCodePath
        case .codex: codexPath
        case .cursor: cursorPath
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

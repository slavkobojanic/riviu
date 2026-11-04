import Foundation

/// AI coding CLIs that Riviu can drive. Each uses whatever account the user signed into it with.
public enum CommandLineTool: String, CaseIterable, Sendable, Codable {
    case claudeCode
    case codex
    case cursor
    /// The Pi coding agent, used for OpenRouter models.
    case pi

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .pi: "Pi"
        }
    }

    public var executableName: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .cursor: "cursor-agent"
        case .pi: "pi"
        }
    }

    public var installHint: String {
        switch self {
        case .claudeCode: "Install Claude Code, then run `claude` once in Terminal to sign in."
        case .codex: "Install the Codex CLI, then run `codex` once in Terminal to sign in."
        case .cursor: "Install the Cursor CLI, then run `cursor-agent login` in Terminal."
        case .pi: "Install the Pi coding agent, then sign in to OpenRouter with it or set OPENROUTER_API_KEY in your shell."
        }
    }

    /// Arguments for a one-shot, read-only, non-interactive run.
    func arguments(prompt: String, model: String?, replyFile: URL) -> [String] {
        var arguments: [String]
        switch self {
        case .claudeCode:
            arguments = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--tools", ""]
            if let model { arguments += ["--model", model] }
        case .codex:
            arguments = ["exec", "--skip-git-repo-check", "--sandbox", "read-only", "--ephemeral", "-o", replyFile.path, prompt]
            if let model { arguments += ["-m", model] }
        case .cursor:
            arguments = ["-p", prompt, "--output-format", "text", "--trust"]
            if let model { arguments += ["--model", model] }
        case .pi:
            // Only the model answers: no tools, saved sessions, extensions, skills or project files.
            arguments = ["-p", "--provider", "openrouter", "--no-tools", "--no-session", "--no-extensions", "--no-skills",
                         "--no-context-files", "--no-prompt-templates", "--no-themes", "--offline"]
            if let model { arguments += ["--model", model] }
            arguments += ["--", prompt]
        }
        return arguments
    }
}

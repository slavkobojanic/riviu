import Foundation

/// AI coding CLIs that Riviu can drive. Each uses whatever account the user signed into it with.
public enum CommandLineTool: String, CaseIterable, Sendable, Codable {
    case claudeCode
    case codex
    case cursor

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    public var executableName: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .cursor: "cursor-agent"
        }
    }

    public var installHint: String {
        switch self {
        case .claudeCode: "Install Claude Code, then run `claude` once in Terminal to sign in."
        case .codex: "Install the Codex CLI, then run `codex` once in Terminal to sign in."
        case .cursor: "Install the Cursor CLI, then run `cursor-agent login` in Terminal."
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
        }
        return arguments
    }
}

import RiviuAI
import RiviuDiff

/// The instructions and context sent to the AI provider.
enum ReviewPrompts {
    /// Keeps prompts comfortably inside every provider's limits (and the command-line argument limit for CLIs).
    private static let maxDiffCharacters = 150_000

    static let defaultChatInstructions = """
    You are a senior engineer helping someone review a pull request in Riviu, a code review app.
    Answer questions about the change concisely and concretely. Refer to files and line numbers.
    Use Markdown. Do not use tools or edit files; everything you need is below.
    """

    static let defaultExplainInstructions = """
    You explain code to someone reviewing a pull request. Say what the code does and, if it changed in this \
    pull request, what changed and why it matters. Point out anything risky. Use Markdown. Do not use tools.
    """

    /// The user's chat instructions followed by the pull request's details and diffs.
    static func chatSystemPrompt(instructions: String, pullRequest: PullRequest, openFile: ChangedFile?) -> String {
        var lines = [
            instructions,
            "",
            "Pull request \(pullRequest.reference.id): \(pullRequest.title)",
            "Author: \(pullRequest.author) · \(pullRequest.headBranch) → \(pullRequest.baseBranch)",
            "Description: \(pullRequest.summary.isEmpty ? "(none)" : pullRequest.summary)",
            "",
            "Changed files:",
        ]
        lines += pullRequest.files.map { "- \($0.path) (+\($0.additions) −\($0.deletions))" }
        if let openFile {
            lines += ["", "The reviewer currently has \(openFile.path) open."]
        }
        lines += ["", "Diffs:", diffs(for: pullRequest, putFirst: openFile)]
        return lines.joined(separator: "\n")
    }

    static func explainRequest(instructions: String, length: ExplanationLength, target: CodeTarget,
                               pullRequest: PullRequest, fileDiff: FileDiff?) -> AIRequest {
        let system = instructions + "\n\n" + length.instruction
        var context = "Pull request \(pullRequest.reference.id): \(pullRequest.title)\n\n"
        if let fileDiff {
            context += "Diff of \(fileDiff.path):\n\(UnifiedDiffText.make(for: fileDiff))\n\n"
        }
        let question = context + "Explain \(target.label) of \(target.filePath):\n```\n\(target.code)\n```"
        return AIRequest(system: system, messages: [AIMessage(role: .user, text: question)])
    }

    static func continueInChatMessage(target: CodeTarget) -> String {
        "Explain \(target.label) of `\(target.filePath)`:\n```\n\(target.code)\n```"
    }

    /// The open file's diff comes first so it survives if the total has to be shortened.
    private static func diffs(for pullRequest: PullRequest, putFirst openFile: ChangedFile?) -> String {
        let others = pullRequest.files.filter { $0.path != openFile?.path }
        let ordered = (openFile.map { [$0] } ?? []) + others
        var result = ""
        for file in ordered {
            guard let patch = file.patch else {
                result += "(No diff available for \(file.path); it may be binary or very large.)\n"
                continue
            }
            let diff = "--- a/\(file.previousPath ?? file.path)\n+++ b/\(file.path)\n\(patch)\n\n"
            if result.count + diff.count > maxDiffCharacters {
                result += "(Diff of \(file.path) omitted for length.)\n"
            } else {
                result += diff
            }
        }
        return result
    }
}

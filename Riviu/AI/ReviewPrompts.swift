import RiviuAI
import RiviuDiff

/// The instructions and context sent to the AI provider.
enum ReviewPrompts {
    /// Keeps prompts comfortably inside every provider's limits (and the command-line argument limit for CLIs).
    private static let maxDiffCharacters = 150_000

    static func defaultInstructions(for task: AITask) -> String {
        switch task {
        case .review: defaultReviewInstructions
        case .chat: defaultChatInstructions
        case .explain: defaultExplainInstructions
        }
    }

    private static let defaultReviewInstructions = """
    You are a senior engineer reviewing a pull request. Look for bugs, security problems, risky changes without tests, \
    and code that will confuse the next reader. Skip style nits a formatter would fix. Be specific and brief.
    """

    private static let defaultChatInstructions = """
    You are a senior engineer helping someone review a pull request in Riviu, a code review app.
    Answer questions about the change concisely and concretely. Refer to files and line numbers.
    Use Markdown. Do not use tools or edit files; everything you need is below.
    """

    private static let defaultExplainInstructions = """
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

    /// Asks for a summary and line-level findings, as JSON that `ReviewReport.parse` reads.
    static func reviewRequest(instructions: String, pullRequest: PullRequest) -> AIRequest {
        let system = instructions + "\n\n" + ReviewReport.formatInstructions
        let question = [
            "Review pull request \(pullRequest.reference.id): \(pullRequest.title)",
            "Author: \(pullRequest.author) · \(pullRequest.headBranch) → \(pullRequest.baseBranch)",
            "Description: \(pullRequest.summary.isEmpty ? "(none)" : pullRequest.summary)",
            "",
            "Diffs:",
            diffs(for: pullRequest, putFirst: nil, numbered: true),
        ].joined(separator: "\n")
        return AIRequest(system: system, messages: [AIMessage(role: .user, text: question)])
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
    private static func diffs(for pullRequest: PullRequest, putFirst openFile: ChangedFile?, numbered: Bool = false) -> String {
        let others = pullRequest.files.filter { $0.path != openFile?.path }
        let ordered = (openFile.map { [$0] } ?? []) + others
        var result = ""
        for file in ordered {
            guard var patch = file.patch else {
                result += "(No diff available for \(file.path); it may be binary or very large.)\n"
                continue
            }
            if numbered {
                patch = NumberedPatch.make(from: patch)
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

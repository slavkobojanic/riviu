import RiviuAI
import RiviuDiff

/// The instructions and context sent to the AI provider.
enum ReviewPrompts {
    /// Keeps prompts comfortably inside every provider's limits (and the command-line argument limit for CLIs).
    private static let maxDiffCharacters = 150_000

    static func chatSystemPrompt(pullRequest: PullRequest, openFile: FileDiff?) -> String {
        var lines = [
            "You are a senior engineer helping someone review a pull request in Riviu, a code review app.",
            "Answer questions about the change concisely and concretely. Refer to files and line numbers.",
            "Use Markdown. Do not use tools or edit files; everything you need is below.",
            "",
            "Pull request #\(pullRequest.number): \(pullRequest.title)",
            "Author: \(pullRequest.author) · Branch: \(pullRequest.branch)",
            "Description: \(pullRequest.summary)",
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

    static func explainRequest(target: CodeTarget, pullRequest: PullRequest) -> AIRequest {
        let file = pullRequest.file(at: target.filePath)
        let system = """
        You explain code to someone reviewing a pull request. Be brief: a short paragraph on what the code does, \
        then, if it changed in this pull request, a short paragraph on what changed and why it matters. \
        Point out anything risky. Use Markdown. Do not use tools.
        """
        var context = "Pull request #\(pullRequest.number): \(pullRequest.title)\n\n"
        if let file {
            context += "Diff of \(file.path):\n\(UnifiedDiffText.make(for: file))\n\n"
        }
        let question = context + "Explain \(target.label) of \(target.filePath):\n```\n\(target.code)\n```"
        return AIRequest(system: system, messages: [AIMessage(role: .user, text: question)])
    }

    static func continueInChatMessage(target: CodeTarget) -> String {
        "Explain \(target.label) of `\(target.filePath)`:\n```\n\(target.code)\n```"
    }

    /// The open file's diff comes first so it survives if the total has to be shortened.
    private static func diffs(for pullRequest: PullRequest, putFirst openFile: FileDiff?) -> String {
        let others = pullRequest.files.filter { $0.path != openFile?.path }
        let ordered = (openFile.map { [$0] } ?? []) + others
        var result = ""
        for file in ordered {
            let diff = UnifiedDiffText.make(for: file) + "\n\n"
            if result.count + diff.count > maxDiffCharacters {
                result += "(Diff of \(file.path) omitted for length.)\n"
            } else {
                result += diff
            }
        }
        return result
    }
}

import Foundation
import RiviuSupport

/// Answers by running an AI CLI (Claude Code, Codex or Cursor) as a child process.
public struct CommandLineProvider: AIProvider {
    public let tool: CommandLineTool
    public let executable: URL
    /// nil uses the CLI's own default model.
    public let model: String?
    public let workingDirectory: URL

    public init(tool: CommandLineTool, executable: URL, model: String?, workingDirectory: URL) {
        self.tool = tool
        self.executable = executable
        self.model = model
        self.workingDirectory = workingDirectory
    }

    public func streamEvents(to request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let prompt = Self.singlePrompt(from: request)
        let replyFile = FileManager.default.temporaryDirectory.appending(path: "riviu-reply-\(UUID().uuidString).txt")
        let child = ChildProcess(executable: executable,
                                 arguments: tool.arguments(prompt: prompt, model: model, replyFile: replyFile),
                                 workingDirectory: workingDirectory)
        let tool = self.tool

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try child.start()
                    for try await line in child.outputLines() {
                        switch tool {
                        case .claudeCode:
                            switch ClaudeCodeStreamParser.parse(line: line) {
                            case let .text(text): continuation.yield(.text(text))
                            case let .thinking(text): continuation.yield(.thinking(text))
                            case let .error(message): throw AIProviderError.commandFailed(message)
                            case .ignored: break
                            }
                        case .cursor, .pi:
                            continuation.yield(.text(line + "\n"))
                        case .codex:
                            break // Codex writes its final answer to `replyFile` instead.
                        }
                    }
                    let result = await child.waitForExit()
                    guard result.status == 0 else {
                        throw AIProviderError.commandFailed(CommandLineErrorText.summary(of: result.errorOutput, tool: tool))
                    }
                    if tool == .codex, let reply = try? String(contentsOf: replyFile, encoding: .utf8) {
                        continuation.yield(.text(reply))
                    }
                    try? FileManager.default.removeItem(at: replyFile)
                    continuation.finish()
                } catch {
                    try? FileManager.default.removeItem(at: replyFile)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                child.stop()
            }
        }
    }

    /// CLIs take one prompt, so the instructions and the conversation are written out as text.
    static func singlePrompt(from request: AIRequest) -> String {
        var parts = [request.system]
        let earlier = request.messages.dropLast()
        if !earlier.isEmpty {
            parts.append("Conversation so far:")
            for message in earlier {
                let speaker = message.role == .user ? "User" : "Assistant"
                parts.append("\(speaker): \(message.text)")
            }
            parts.append("Reply to the user's latest message:")
        }
        if let latest = request.messages.last {
            parts.append(latest.text)
        }
        return parts.joined(separator: "\n\n")
    }
}

/// Reads Claude Code's `--output-format stream-json` lines.
enum ClaudeCodeStreamParser {
    enum Output: Equatable {
        case text(String)
        /// Claude Code leaves this empty in print mode, but passes it on if that changes.
        case thinking(String)
        case error(String)
        case ignored
    }

    private struct Line: Decodable {
        struct Event: Decodable {
            struct Delta: Decodable {
                let type: String?
                let text: String?
                let thinking: String?
            }
            let type: String
            let delta: Delta?
        }

        let type: String
        let event: Event?
        let is_error: Bool?
        let result: String?
    }

    static func parse(line: String) -> Output {
        guard let decoded = try? JSONDecoder().decode(Line.self, from: Data(line.utf8)) else { return .ignored }
        if decoded.type == "stream_event", decoded.event?.type == "content_block_delta", decoded.event?.delta?.type == "text_delta" {
            return .text(decoded.event?.delta?.text ?? "")
        }
        if decoded.type == "stream_event", decoded.event?.type == "content_block_delta",
           decoded.event?.delta?.type == "thinking_delta", let thinking = decoded.event?.delta?.thinking, !thinking.isEmpty {
            return .thinking(thinking)
        }
        if decoded.type == "result", decoded.is_error == true {
            return .error(decoded.result ?? "Claude Code reported an error.")
        }
        return .ignored
    }
}

/// Turns a CLI's stderr into one readable sentence.
enum CommandLineErrorText {
    static func summary(of errorOutput: String, tool: CommandLineTool) -> String {
        let lines = errorOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let line = lines.last { $0.localizedCaseInsensitiveContains("error") } ?? lines.last
        guard let line else { return "\(tool.displayName) exited with an error." }
        return messageField(in: line) ?? line
    }

    /// CLIs often print `ERROR: {"error": {"message": "…"}}`; this pulls out the message.
    private static func messageField(in line: String) -> String? {
        guard let start = line.firstIndex(of: "{"),
              let object = try? JSONSerialization.jsonObject(with: Data(line[start...].utf8)) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return object["message"] as? String
    }
}

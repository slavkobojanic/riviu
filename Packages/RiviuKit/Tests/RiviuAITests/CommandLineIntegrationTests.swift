import Foundation
import Testing
@testable import RiviuAI
import RiviuSupport

/// Runs the real Claude Code CLI. Opt in with `RIVIU_INTEGRATION_TESTS=1 swift test`.
struct CommandLineIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RIVIU_INTEGRATION_TESTS"] == "1"))
    func claudeCodeStreamsAReply() async throws {
        let executable = try #require(ExecutableLocator.find("claude"))
        let provider = CommandLineProvider(tool: .claudeCode, executable: executable, model: nil,
                                           workingDirectory: FileManager.default.temporaryDirectory.appending(path: "riviu-tests"))
        let request = AIRequest(system: "You are a test.", messages: [AIMessage(role: .user, text: "Reply with the single word OK.")])
        var chunks: [String] = []
        for try await chunk in provider.streamReply(to: request) {
            chunks.append(chunk)
        }
        #expect(chunks.joined().contains("OK"))
    }
}

import Testing
@testable import RiviuAI

struct AnthropicStreamParserTests {
    @Test func readsTextDeltas() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        #expect(AnthropicStreamParser.parse(line: line) == .text("Hello"))
    }

    @Test func readsThinkingSummaries() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Checking the diff"}}"#
        #expect(AnthropicStreamParser.parse(line: line) == .thinking("Checking the diff"))
    }

    @Test func skipsEventNamesAndOtherEvents() {
        #expect(AnthropicStreamParser.parse(line: "event: content_block_delta") == .ignored)
        #expect(AnthropicStreamParser.parse(line: #"data: {"type":"message_stop"}"#) == .ignored)
    }

    @Test func reportsRefusalsAndErrors() {
        #expect(AnthropicStreamParser.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#) == .refused)
        #expect(AnthropicStreamParser.parse(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#) == .error("Overloaded"))
    }

    @Test func extractsErrorMessagesFromResponseBodies() {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        #expect(AnthropicStreamParser.errorMessage(in: body) == "invalid x-api-key")
    }
}

struct ClaudeCodeStreamParserTests {
    @Test func readsPartialText() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"OK"}},"session_id":"x"}"#
        #expect(ClaudeCodeStreamParser.parse(line: line) == .text("OK"))
    }

    @Test func readsThinkingButSkipsEmptyThinking() {
        let thought = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Hmm"}}}"#
        let empty = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}}"#
        #expect(ClaudeCodeStreamParser.parse(line: thought) == .thinking("Hmm"))
        #expect(ClaudeCodeStreamParser.parse(line: empty) == .ignored)
    }

    @Test func reportsErrorResults() {
        let line = #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Not logged in"}"#
        #expect(ClaudeCodeStreamParser.parse(line: line) == .error("Not logged in"))
    }
}

struct CommandLineProviderTests {
    @Test func flattensTheConversationIntoOnePrompt() {
        let request = AIRequest(system: "Be brief.", messages: [
            AIMessage(role: .user, text: "Hi"),
            AIMessage(role: .assistant, text: "Hello"),
            AIMessage(role: .user, text: "What changed?"),
        ])
        let prompt = CommandLineProvider.singlePrompt(from: request)
        #expect(prompt == "Be brief.\n\nConversation so far:\n\nUser: Hi\n\nAssistant: Hello\n\nReply to the user's latest message:\n\nWhat changed?")
    }

    @Test func summarisesCodexStyleErrors() {
        let stderr = "starting…\nERROR: {\"type\":\"error\",\"status\":400,\"error\":{\"message\":\"Model not supported\"}}"
        #expect(CommandLineErrorText.summary(of: stderr, tool: .codex) == "Model not supported")
    }
}

import Foundation

/// Talks to the Claude API directly with an API key, streaming the reply over server-sent events.
public struct AnthropicAPIProvider: AIProvider {
    public static let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
    public static let defaultModel = "claude-opus-5-5"

    private static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let modelsURL = URL(string: "https://api.anthropic.com/v1/models")!
    private static let apiVersion = "2026-10-21"

    public let apiKey: String
    public let model: String

    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    public func streamReply(to request: AIRequest) -> AsyncThrowingStream<String, Error> {
        let urlRequest = makeRequest(for: request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw AIProviderError.requestFailed(status: status, message: AnthropicStreamParser.errorMessage(in: body))
                    }
                    for try await line in bytes.lines {
                        switch AnthropicStreamParser.parse(line: line) {
                        case let .text(text): continuation.yield(text)
                        case .refused: throw AIProviderError.refused
                        case let .error(message): throw AIProviderError.requestFailed(status: status, message: message)
                        case .ignored: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Checks that a key is accepted, by listing models.
    public static func verify(apiKey: String) async throws {
        var request = URLRequest(url: modelsURL)
        addHeaders(to: &request, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw AIProviderError.requestFailed(status: status,
                                                message: AnthropicStreamParser.errorMessage(in: String(decoding: data, as: UTF8.self)))
        }
    }

    private func makeRequest(for request: AIRequest) -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 32_000,
            "stream": true,
            "system": request.system,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]

        var urlRequest = URLRequest(url: Self.messagesURL)
        urlRequest.httpMethod = "POST"
        Self.addHeaders(to: &urlRequest, apiKey: apiKey)

        // On Opus and Sonnet, a declined request is retried on Anthropic's recommended fallback model.
        if model == "claude-opus-5-5" || model == "claude-sonnet-5-5" {
            body["fallbacks"] = "default"
            urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private static func addHeaders(to request: inout URLRequest, apiKey: String) {
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
    }
}

/// Reads the lines of a Claude API event stream.
enum AnthropicStreamParser {
    enum Output: Equatable {
        case text(String)
        case refused
        case error(String)
        case ignored
    }

    private struct Event: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stop_reason: String?
        }

        struct ErrorBody: Decodable {
            let message: String
        }

        let type: String
        let delta: Delta?
        let error: ErrorBody?
    }

    /// Each `data:` line carries one JSON event; `event:` lines and blank lines repeat the type, so they're skipped.
    static func parse(line: String) -> Output {
        guard line.hasPrefix("data:") else { return .ignored }
        let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let event = try? JSONDecoder().decode(Event.self, from: Data(json.utf8)) else { return .ignored }

        switch event.type {
        case "content_block_delta" where event.delta?.type == "text_delta":
            return .text(event.delta?.text ?? "")
        case "message_delta" where event.delta?.stop_reason == "refusal":
            return .refused
        case "error":
            return .error(event.error?.message ?? "Unknown error")
        default:
            return .ignored
        }
    }

    /// Pulls `error.message` out of an error response body, or returns the body itself.
    static func errorMessage(in body: String) -> String {
        struct ErrorResponse: Decodable {
            struct Body: Decodable { let message: String }
            let error: Body
        }
        let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: Data(body.utf8))
        return decoded?.error.message ?? body
    }
}

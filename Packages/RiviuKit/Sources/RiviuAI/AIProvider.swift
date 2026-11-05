import Foundation

public struct AIMessage: Sendable, Equatable, Codable {
    public enum Role: String, Sendable, Codable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct AIRequest: Sendable {
    /// Instructions and background (for example the pull request diff).
    public var system: String
    /// The conversation so far, oldest first, ending with the user's latest message.
    public var messages: [AIMessage]

    public init(system: String, messages: [AIMessage]) {
        self.system = system
        self.messages = messages
    }
}

/// A piece of a streamed reply.
public enum AIStreamEvent: Sendable, Equatable {
    /// More of the answer.
    case text(String)
    /// More of the model's summarized reasoning, from providers that share it.
    case thinking(String)
}

/// Something that can answer a conversation, streaming the reply as it is written.
public protocol AIProvider: Sendable {
    func streamEvents(to request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
}

public enum AIProviderError: LocalizedError, Equatable {
    case missingAPIKey
    case executableNotFound(String)
    case commandFailed(String)
    case requestFailed(status: Int, message: String)
    case refused

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No API key is saved. Add one in Settings → AI."
        case let .executableNotFound(name):
            "Couldn't find “\(name)”. Install it, or set its path in Settings → AI."
        case let .commandFailed(message):
            message
        case let .requestFailed(status, message):
            "The request failed (\(status)): \(message)"
        case .refused:
            "The model declined to answer this request."
        }
    }
}

extension AIProvider {
    /// Just the answer, without the reasoning.
    public func streamReply(to request: AIRequest) -> AsyncThrowingStream<String, Error> {
        let events = streamEvents(to: request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        if case let .text(text) = event { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Collects a whole reply. Handy for connection tests.
    public func reply(to request: AIRequest) async throws -> String {
        var text = ""
        for try await chunk in streamReply(to: request) {
            text += chunk
        }
        return text
    }
}

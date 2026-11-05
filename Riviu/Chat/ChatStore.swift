import Foundation
import Observation
import RiviuAI

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: AIMessage.Role
    var text: String
    var isError = false
    /// The model's summarized reasoning, from providers that share it.
    var thinking: String?
    /// How long the model thought before it started answering.
    var thoughtSeconds: Int?

    init(role: AIMessage.Role, text: String, isError: Bool = false) {
        id = UUID()
        self.role = role
        self.text = text
        self.isError = isError
    }
}

/// One conversation about one pull request.
struct Chat: Identifiable, Codable {
    let id: UUID
    let pullRequest: PullRequestReference
    let pullRequestTitle: String
    var title: String
    var messages: [ChatMessage]
    var updatedAt: Date
}

/// All AI chats, saved to disk so the history survives relaunches.
@Observable
final class ChatStore {
    /// Newest first.
    private(set) var chats: [Chat] = []
    /// The chat shown in the panel. nil shows an empty new chat for the current pull request.
    var activeChatID: UUID?
    private(set) var isReplying = false
    /// When the current reply was asked for, to show how long the model has been thinking.
    private(set) var replyStartedAt: Date?

    @ObservationIgnored private let makeProvider: () throws -> AIProvider
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private let fileURL = URL.applicationSupportDirectory.appending(path: "Riviu/chat-history.json")

    init(makeProvider: @escaping () throws -> AIProvider) {
        self.makeProvider = makeProvider
        load()
    }

    var activeChat: Chat? {
        chats.first { $0.id == activeChatID }
    }

    func chats(about pullRequest: PullRequestReference) -> [Chat] {
        chats.filter { $0.pullRequest == pullRequest }
    }

    /// Shows the most recent chat about this pull request, or an empty one if there isn't any.
    func showLatestChat(about pullRequest: PullRequestReference) {
        if activeChat?.pullRequest == pullRequest { return }
        activeChatID = chats(about: pullRequest).first?.id
    }

    func startNewChat() {
        stopReplying()
        activeChatID = nil
    }

    func deleteChat(_ id: UUID) {
        if id == activeChatID { startNewChat() }
        chats.removeAll { $0.id == id }
        save()
    }

    func send(_ text: String, pullRequest: PullRequest, systemPrompt: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isReplying else { return }

        let chatID = activeChatID(forSending: text, pullRequest: pullRequest)
        update(chatID) { $0.messages.append(ChatMessage(role: .user, text: text)) }
        let history = chats.first { $0.id == chatID }?.messages.filter { !$0.isError }.map { AIMessage(role: $0.role, text: $0.text) } ?? []
        update(chatID) { $0.messages.append(ChatMessage(role: .assistant, text: "")) }

        isReplying = true
        let startedAt = Date.now
        replyStartedAt = startedAt
        replyTask = Task {
            do {
                let provider = try makeProvider()
                for try await event in provider.streamEvents(to: AIRequest(system: systemPrompt, messages: history)) {
                    updateLastMessage(in: chatID) { message in
                        switch event {
                        case let .text(text):
                            if message.thoughtSeconds == nil {
                                message.thoughtSeconds = Int(Date.now.timeIntervalSince(startedAt))
                            }
                            message.text += text
                        case let .thinking(text):
                            message.thinking = (message.thinking ?? "") + text
                        }
                    }
                }
            } catch is CancellationError {
                // Stopped by the user; keep whatever arrived.
            } catch {
                updateLastMessage(in: chatID) { message in
                    message.text = error.localizedDescription
                    message.isError = true
                }
            }
            isReplying = false
            replyStartedAt = nil
            save()
        }
    }

    func stopReplying() {
        replyTask?.cancel()
        replyTask = nil
        isReplying = false
        replyStartedAt = nil
    }

    // MARK: - Helpers

    /// Uses the active chat if it belongs to this pull request, otherwise starts one titled after the first message.
    private func activeChatID(forSending text: String, pullRequest: PullRequest) -> UUID {
        if let chat = activeChat, chat.pullRequest == pullRequest.reference {
            return chat.id
        }
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        let chat = Chat(id: UUID(), pullRequest: pullRequest.reference, pullRequestTitle: pullRequest.title,
                        title: String(firstLine.prefix(60)), messages: [], updatedAt: .now)
        chats.insert(chat, at: 0)
        activeChatID = chat.id
        return chat.id
    }

    private func update(_ chatID: UUID, _ change: (inout Chat) -> Void) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else { return }
        change(&chats[index])
        chats[index].updatedAt = .now
        if index != 0 {
            chats.insert(chats.remove(at: index), at: 0)
        }
    }

    private func updateLastMessage(in chatID: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }), !chats[index].messages.isEmpty else { return }
        change(&chats[index].messages[chats[index].messages.count - 1])
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        chats = (try? JSONDecoder().decode([Chat].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(chats).write(to: fileURL, options: .atomic)
        } catch {
            print("Couldn't save chats: \(error)")
        }
    }
}

import RiviuAI
import RiviuDiff
import RiviuMarkdown
import SwiftUI

/// AI chat about the current pull request, with a history of earlier chats.
struct ChatPanel: View {
    let chats: ChatStore
    let workspace: ReviewWorkspace
    @State private var showsHistory = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showsHistory {
                ChatHistoryList(chats: chats, workspace: workspace) { showsHistory = false }
            } else if let pullRequest = workspace.pullRequest {
                ChatConversation(chats: chats, workspace: workspace, pullRequest: pullRequest)
            } else {
                ContentUnavailableView("No Pull Request Open", systemImage: "sparkles",
                                       description: Text("Open a pull request to chat about it."))
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(showsHistory ? "Chat History" : (chats.activeChat?.title ?? "New Chat"))
                    .font(.headline)
                    .lineLimit(1)
                if let pullRequest = workspace.pullRequest {
                    Text("\(pullRequest.reference.id)  \(pullRequest.title)")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle(isOn: $showsHistory) {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .toggleStyle(.button)
            .help("Show previous chats")
            Button("New Chat", systemImage: "square.and.pencil") {
                chats.startNewChat()
                showsHistory = false
            }
            .help("Start a new chat about this pull request")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(12)
    }
}

private struct ChatConversation: View {
    let chats: ChatStore
    let workspace: ReviewWorkspace
    let pullRequest: PullRequest
    @Environment(AppSettings.self) private var settings
    @State private var draft = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let chat = chats.activeChat, chat.pullRequest == pullRequest.reference {
                        ForEach(chat.messages) { message in
                            ChatMessageRow(message: message, isStreaming: chats.isReplying && message.id == chat.messages.last?.id)
                                .id(message.id)
                        }
                    } else {
                        suggestions
                    }
                }
                .padding(14)
            }
            .onChange(of: chats.activeChat?.messages.last?.text) {
                if let last = chats.activeChat?.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            ChatComposer(draft: $draft, isReplying: chats.isReplying,
                         send: { send(draft) }, stop: { chats.stopReplying() })
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ask about #\(pullRequest.number)", systemImage: "sparkles")
                .font(.headline)
            ForEach(suggestedQuestions, id: \.self) { question in
                Button(question) { send(question) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var suggestedQuestions: [String] {
        var questions = ["Summarize this pull request", "What's the riskiest part of this change?"]
        if let file = workspace.selectedFile {
            questions.append("What changed in \(file.fileName)?")
        }
        return questions
    }

    private func send(_ text: String) {
        chats.send(text, pullRequest: pullRequest,
                   systemPrompt: ReviewPrompts.chatSystemPrompt(instructions: settings.chatInstructions, pullRequest: pullRequest,
                                                                openFile: workspace.selectedFile))
        draft = ""
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.18), in: .rect(cornerRadius: 14))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                if message.isError {
                    AIErrorView(message: message.text)
                } else if message.text.isEmpty && isStreaming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    StructuredText(markdown: message.text)
                        .textual.textSelection(.enabled)
                }
            }
        }
    }
}

private struct ChatHistoryList: View {
    let chats: ChatStore
    let workspace: ReviewWorkspace
    let onOpen: () -> Void

    var body: some View {
        if chats.chats.isEmpty {
            ContentUnavailableView("No Chats Yet", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Chats you have about a pull request show up here."))
        } else {
            List {
                ForEach(pullRequests, id: \.self) { reference in
                    Section(sectionTitle(for: reference)) {
                        ForEach(chats.chats(about: reference)) { chat in
                            row(for: chat)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    /// Pull requests in the order their latest chat happened.
    private var pullRequests: [PullRequestReference] {
        var seen = Set<PullRequestReference>()
        return chats.chats.map(\.pullRequest).filter { seen.insert($0).inserted }
    }

    private func sectionTitle(for reference: PullRequestReference) -> String {
        let title = chats.chats.first { $0.pullRequest == reference }?.pullRequestTitle ?? ""
        return "\(reference.id) \(title)"
    }

    private func row(for chat: Chat) -> some View {
        Button {
            workspace.open(chat.pullRequest)
            chats.activeChatID = chat.id
            onOpen()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.title)
                        .lineLimit(1)
                    Text(chat.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                }
                Spacer()
                if chat.id == chats.activeChatID {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Chat", role: .destructive) { chats.deleteChat(chat.id) }
        }
    }
}

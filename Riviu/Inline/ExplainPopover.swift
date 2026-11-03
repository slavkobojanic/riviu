import RiviuAI
import RiviuMarkdown
import SwiftUI

/// Streams an AI explanation of the selected code.
struct ExplainPopover: View {
    let target: CodeTarget
    let request: AIRequest
    let makeProvider: () throws -> AIProvider
    let onContinueInChat: () -> Void

    @State private var answer = ""
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Explain", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button("Continue in Chat", systemImage: "bubble.left.and.text.bubble.right", action: onContinueInChat)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            Text("\((target.filePath as NSString).lastPathComponent) · \(target.label)")
                .font(.caption)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    codePreview
                    answerView
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: 460, height: 420, alignment: .topLeading)
        .task { await streamAnswer() }
    }

    private var codePreview: some View {
        Text(target.code)
            .font(.system(.callout, design: .monospaced))
            .lineLimit(8)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.background.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    private var answerView: some View {
        if let errorMessage {
            AIErrorView(message: errorMessage)
        } else if answer.isEmpty && isLoading {
            ProgressView("Thinking…")
                .controlSize(.small)
        } else {
            StructuredText(markdown: answer)
                .textual.textSelection(.enabled)
        }
    }

    private func streamAnswer() async {
        do {
            let provider = try makeProvider()
            for try await chunk in provider.streamReply(to: request) {
                answer += chunk
            }
        } catch is CancellationError {
            // The popover closed.
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// An AI error with a shortcut to the settings where it can usually be fixed.
struct AIErrorView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            SettingsLink {
                Text("Open AI Settings…")
            }
            .controlSize(.small)
        }
    }
}

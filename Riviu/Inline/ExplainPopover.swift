import AppKit
import RiviuAI
import RiviuDiff
import RiviuMarkdown
import SwiftUI

/// Streams an AI explanation of the selected code. Changing the length asks again.
struct ExplainPopover: View {
    let target: CodeTarget
    let pullRequest: PullRequest
    let fileDiff: FileDiff?
    @Bindable var settings: AppSettings
    let onContinueInChat: () -> Void

    @State private var answer = ""
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            CodeSnippet(code: target.code)
            answerSection
            Divider()
            footer
        }
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: settings.explanationLength) { await streamAnswer() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Explain", systemImage: "sparkles")
                    .font(.headline)
                Text("\((target.filePath as NSString).lastPathComponent) · \(target.label)")
                    .font(.caption)
            }
            Spacer()
            Picker("Length", selection: $settings.explanationLength) {
                ForEach(ExplanationLength.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("How long explanations should be")
        }
    }

    @ViewBuilder
    private var answerSection: some View {
        if let errorMessage {
            AIErrorView(message: errorMessage)
        } else if answer.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Asking \(AISetup.description(of: .explain, settings: settings))…")
                    .font(.callout)
            }
            .padding(.vertical, 4)
        } else {
            ScrollView {
                StructuredText(markdown: answer)
                    .textual.textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(AISetup.description(of: .explain, settings: settings))
                .font(.caption)
                .lineLimit(1)
            if isLoading && !answer.isEmpty {
                ProgressView()
                    .controlSize(.mini)
            }
            Spacer()
            Button("Copy", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(answer, forType: .string)
            }
            .disabled(answer.isEmpty)
            Button("Continue in Chat", systemImage: "bubble.left.and.text.bubble.right", action: onContinueInChat)
                .buttonStyle(.glassProminent)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    private func streamAnswer() async {
        answer = ""
        errorMessage = nil
        isLoading = true
        let request = ReviewPrompts.explainRequest(instructions: settings.explainInstructions, length: settings.explanationLength,
                                                   target: target, pullRequest: pullRequest, fileDiff: fileDiff)
        do {
            let provider = try AISetup.makeProvider(for: .explain, settings: settings)
            for try await chunk in provider.streamReply(to: request) {
                answer += chunk
            }
        } catch is CancellationError {
            // Closed, or the length changed and a new answer started.
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// A few lines of code with their shared indentation removed.
private struct CodeSnippet: View {
    let code: String
    private let maxLines = 6

    var body: some View {
        let lines = Self.withoutCommonIndentation(code.components(separatedBy: "\n"))
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.prefix(maxLines).enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if lines.count > maxLines {
                Text("+ \(lines.count - maxLines) more lines")
                    .font(.caption)
            }
        }
        .font(.system(.callout, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.opacity(0.55), in: .rect(cornerRadius: 8))
    }

    static func withoutCommonIndentation(_ lines: [String]) -> [String] {
        let indents = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0 == " " || $0 == "\t" }.count }
        let common = indents.min() ?? 0
        return lines.map { String($0.dropFirst(min(common, $0.count))) }
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

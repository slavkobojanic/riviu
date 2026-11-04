import RiviuMarkdown
import SwiftUI

/// Writing a comment: a Markdown editor with formatting buttons and a live preview underneath.
struct CommentComposer: View {
    let comment: ReviewComment
    let workspace: ReviewWorkspace

    @State private var draft = ""
    @State private var selection: TextSelection?
    @State private var showsPreview = true
    @State private var polished: String?
    @State private var isPolishing = false
    @State private var polishError: String?
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            formattingBar
            editor
            if let polished {
                PolishedComment(original: draft, polished: polished,
                                onUse: { draft = polished; self.polished = nil },
                                onDiscard: { self.polished = nil })
            } else if showsPreview && !isDraftEmpty {
                preview
            }
            if let polishError {
                AIErrorView(message: polishError)
            }
            footer
        }
        .foregroundStyle(.primary)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onAppear {
            draft = comment.body
            isEditorFocused = true
        }
    }

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.body.weight(.semibold))
            Text("Comment on \(comment.lineLabel)")
                .font(.headline)
            Spacer()
            Toggle("Preview", isOn: $showsPreview)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private var formattingBar: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                formatButton("Bold", symbol: "bold") { wrapSelection(in: "**", "**", placeholder: "bold") }
                formatButton("Italic", symbol: "italic") { wrapSelection(in: "_", "_", placeholder: "italic") }
                formatButton("Code", symbol: "chevron.left.forwardslash.chevron.right") { wrapSelection(in: "`", "`", placeholder: "code") }
                formatButton("Link", symbol: "link") { wrapSelection(in: "[", "](https://)", placeholder: "title") }
                formatButton("Bulleted List", symbol: "list.bullet") { prefixCurrentLine(with: "- ") }
                formatButton("Quote", symbol: "text.quote") { prefixCurrentLine(with: "> ") }
                Spacer()
                Button(isPolishing ? "Polishing…" : "Polish", systemImage: "wand.and.sparkles", action: polish)
                    .disabled(isDraftEmpty || isPolishing)
                    .help("Rewrite this note as a clear, labelled comment with AI (⌥⌘P)")
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button("Suggest Change", systemImage: "plus.forwardslash.minus") {
                    insertBlock("```suggestion\n\(comment.code)\n```\n")
                }
                .help("Insert a GitHub suggestion with the selected code")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var editor: some View {
        TextEditor(text: $draft, selection: $selection)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .focused($isEditorFocused)
            .frame(height: editorHeight)
            .padding(8)
            .background(.background.opacity(0.55), in: .rect(cornerRadius: 10))
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.caption.weight(.semibold))
            StructuredText(markdown: draft)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.3), in: .rect(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Text("Markdown supported  ⌘↩ to add")
                .font(.caption)
            Spacer()
            Button("Cancel") { workspace.cancelEditing(comment.id) }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button(comment.isNew ? "Add Comment" : "Save") { workspace.saveComment(comment.id, body: draft) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isDraftEmpty)
        }
    }

    /// Grows with the text, up to a limit.
    private var editorHeight: CGFloat {
        let lineCount = draft.filter { $0 == "\n" }.count + 1
        return min(260, max(72, CGFloat(lineCount) * 18 + 12))
    }

    private func formatButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .help(title)
    }

    private func polish() {
        isPolishing = true
        polishError = nil
        Task {
            do {
                polished = try await workspace.polish(draft, for: comment)
            } catch {
                polishError = error.localizedDescription
            }
            isPolishing = false
        }
    }

    // MARK: - Editing the draft

    private var selectedRange: Range<String.Index>? {
        guard case let .selection(range)? = selection?.indices, range.upperBound <= draft.endIndex else { return nil }
        return range
    }

    private func wrapSelection(in prefix: String, _ suffix: String, placeholder: String) {
        if let range = selectedRange, !range.isEmpty {
            draft.replaceSubrange(range, with: prefix + draft[range] + suffix)
        } else if let range = selectedRange {
            draft.insert(contentsOf: prefix + placeholder + suffix, at: range.lowerBound)
        } else {
            draft += prefix + placeholder + suffix
        }
        finishEdit()
    }

    private func prefixCurrentLine(with prefix: String) {
        let cursor = selectedRange?.lowerBound ?? draft.endIndex
        let lineStart = draft[..<cursor].lastIndex(of: "\n").map { draft.index(after: $0) } ?? draft.startIndex
        draft.insert(contentsOf: prefix, at: lineStart)
        finishEdit()
    }

    private func insertBlock(_ block: String) {
        if let range = selectedRange {
            draft.replaceSubrange(range, with: block)
        } else {
            let needsNewline = !draft.isEmpty && !draft.hasSuffix("\n")
            draft += (needsNewline ? "\n" : "") + block
        }
        finishEdit()
    }

    private func finishEdit() {
        selection = nil
        isEditorFocused = true
    }
}

/// The AI's rewrite next to your note, so you can compare before using it.
private struct PolishedComment: View {
    let original: String
    let polished: String
    let onUse: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                column(title: "Your note", markdown: original)
                column(title: "Polished", markdown: polished)
            }
            HStack {
                Spacer()
                Button("Keep Mine", action: onDiscard)
                    .buttonStyle(.bordered)
                Button("Use Polished", action: onUse)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.purple.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    private func column(title: String, markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            StructuredText(markdown: markdown)
                .textual.textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

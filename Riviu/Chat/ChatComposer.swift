import SwiftUI

/// The message box at the bottom of the chat, with a Send (or Stop) button.
struct ChatComposer: View {
    @Binding var draft: String
    let isReplying: Bool
    let send: () -> Void
    let stop: () -> Void

    private let buttonSize: CGFloat = 28
    private let cornerRadius: CGFloat = 20

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about this pull request…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .frame(minHeight: buttonSize)
                .onSubmit { if canSend { send() } }
            actionButton
        }
        .padding(.leading, 14)
        .padding([.trailing, .vertical], 6)
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        .padding(10)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isReplying {
            Button("Stop", systemImage: "stop.fill", action: stop)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .frame(width: buttonSize, height: buttonSize)
        } else {
            Button("Send", systemImage: "arrow.up", action: send)
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .frame(width: buttonSize, height: buttonSize)
                .disabled(!canSend)
        }
    }
}

#Preview("Empty") {
    @Previewable @State var draft = ""
    ChatComposer(draft: $draft, isReplying: false, send: {}, stop: {})
        .frame(width: 340)
}

#Preview("Long draft") {
    @Previewable @State var draft = "Why does the retry loop back off linearly instead of exponentially? It seems like it could hammer the API when GitHub is already struggling."
    ChatComposer(draft: $draft, isReplying: false, send: {}, stop: {})
        .frame(width: 340)
}

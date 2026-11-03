import SwiftUI

/// The floating find field shown over the top-right of the diff.
struct FindBar: View {
    @Bindable var workspace: ReviewWorkspace
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField("Find in file", text: $workspace.findQuery)
                .textFieldStyle(.plain)
                .frame(width: 220)
                .focused($isFieldFocused)
                .onSubmit { workspace.findNext() }
            Text(statusText)
                .monospacedDigit()
                .font(.callout)
            Button("Previous Match", systemImage: "chevron.up") { workspace.findPrevious() }
                .labelStyle(.iconOnly)
            Button("Next Match", systemImage: "chevron.down") { workspace.findNext() }
                .labelStyle(.iconOnly)
            Button("Close", systemImage: "xmark") { workspace.hideFind() }
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .onAppear { isFieldFocused = true }
        .onExitCommand { workspace.hideFind() }
    }

    private var statusText: String {
        let status = workspace.findStatus
        if workspace.findQuery.isEmpty { return "" }
        if status.total == 0 { return "No matches" }
        return "\(status.current + 1) of \(status.total)"
    }
}

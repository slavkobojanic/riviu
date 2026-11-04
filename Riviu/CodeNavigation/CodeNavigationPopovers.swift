import RiviuDiff
import RiviuMarkdown
import RiviuSyntax
import SwiftUI

/// What calls the selected code and what it calls, as real code from the repository.
struct HotPathPopover: View {
    let target: CodeTarget
    let workspace: ReviewWorkspace
    let close: () -> Void

    @State private var explanation: String?
    @State private var isExplaining = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hot Path", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            IndexStatus(workspace: workspace) { index in
                if target.side == .base {
                    Text("The hot path follows the new version of the code. Pick added or unchanged lines.")
                        .font(.callout)
                } else {
                    content(index: index)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: 620)
        .onAppear { workspace.prepareCodeIndex() }
    }

    private func finder(_ index: SymbolIndex) -> HotPathFinder {
        HotPathFinder(index: index, changedLines: workspace.changedHeadLines)
    }

    @ViewBuilder
    private func content(index: SymbolIndex) -> some View {
        let finder = finder(index)
        let focus = finder.focus(path: target.filePath, line: target.lines.lowerBound)
        let callers = focus.map(finder.callers) ?? []
        let callees = finder.callees(inside: focus?.lines ?? target.lines, of: target.filePath, excluding: focus)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HotPathSection(title: "Called by", empty: focus == nil ? "This code isn't inside a function." : "No callers found in the repository.") {
                    ForEach(callers) { item in
                        CallerRow(item: item, finder: finder, workspace: workspace, depth: 1, close: close)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(focus.map { "\($0.name)()  \((target.filePath as NSString).lastPathComponent)" } ?? (target.filePath as NSString).lastPathComponent)
                        .font(.headline)
                    Text(target.label)
                        .font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 10))
                HotPathSection(title: "Calls", empty: "No calls to functions defined in the repository.") {
                    ForEach(callees) { item in
                        ExcerptView(title: item.title, excerpt: item.excerpt, workspace: workspace, close: close)
                    }
                }
                explainSection(focus: focus, callers: callers, callees: callees)
            }
        }
        .frame(maxHeight: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func explainSection(focus: SymbolLocation?, callers: [HotPathItem], callees: [HotPathItem]) -> some View {
        if let explanation {
            StructuredText(markdown: explanation)
                .textual.textSelection(.enabled)
        } else if let errorMessage {
            AIErrorView(message: errorMessage)
        }
        if explanation == nil {
            Button(isExplaining ? "Explaining…" : "Explain This Path", systemImage: "sparkles") {
                isExplaining = true
                errorMessage = nil
                Task {
                    do {
                        explanation = try await workspace.explainHotPath(focus: focus.map { "\($0.name)()" } ?? target.label,
                                                                         code: target.code, callers: callers, callees: callees)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isExplaining = false
                }
            }
            .buttonStyle(.bordered)
            .disabled(isExplaining || (callers.isEmpty && callees.isEmpty))
        }
    }
}

/// A caller, which can be opened to show its own callers, up to three steps away.
private struct CallerRow: View {
    let item: HotPathItem
    let finder: HotPathFinder
    let workspace: ReviewWorkspace
    let depth: Int
    let close: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ExcerptView(title: item.title, excerpt: item.excerpt, workspace: workspace, close: close)
            if let function = item.function, depth < 3 {
                DisclosureGroup(isExpanded: $isExpanded) {
                    let callers = finder.callers(of: function)
                    VStack(alignment: .leading, spacing: 6) {
                        if callers.isEmpty {
                            Text("Nothing calls \(function.name)().")
                                .font(.caption)
                        }
                        ForEach(callers) { caller in
                            CallerRow(item: caller, finder: finder, workspace: workspace, depth: depth + 1, close: close)
                        }
                    }
                    .padding(.leading, 14)
                } label: {
                    Text("Who calls \(function.name)()?")
                        .font(.caption)
                }
            }
        }
    }
}

private struct HotPathSection<Content: View>: View {
    let title: String
    let empty: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Group(subviews: content) { subviews in
                if subviews.isEmpty {
                    Text(empty)
                        .font(.callout)
                } else {
                    subviews
                }
            }
        }
    }
}

/// Where a name is defined. Opens straight away when there's one definition in the pull request.
struct DefinitionPopover: View {
    let name: String
    let workspace: ReviewWorkspace
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Definition of \(name)", systemImage: "arrow.right.circle")
                .font(.headline)
            IndexStatus(workspace: workspace) { index in
                let definitions = index.definitions(named: name).prefix(6)
                if definitions.isEmpty {
                    Text("No definition of \(name) found in the repository.")
                        .font(.callout)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(definitions), id: \.self) { definition in
                                let finder = HotPathFinder(index: index, changedLines: workspace.changedHeadLines)
                                let shown = definition.lines.lowerBound...min(definition.lines.upperBound, definition.lines.lowerBound + 14)
                                ExcerptView(title: definition.kind.capitalized, excerpt: finder.excerpt(path: definition.path, lines: shown,
                                                                                                         focus: definition.lines.lowerBound),
                                            workspace: workspace, close: close)
                            }
                        }
                    }
                    .frame(maxHeight: 480)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: 560)
        .onAppear { workspace.prepareCodeIndex() }
    }
}

/// Progress while the repository is downloaded and indexed, then the content.
private struct IndexStatus<Content: View>: View {
    let workspace: ReviewWorkspace
    @ViewBuilder let content: (SymbolIndex) -> Content

    var body: some View {
        switch workspace.codeIndexState {
        case let .ready(index):
            content(index)
        case let .building(message):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.callout)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.statusOrange)
        case nil:
            ProgressView()
                .controlSize(.small)
        }
    }
}

/// A few numbered lines of code, with this pull request's changes tinted.
private struct ExcerptView: View {
    let title: String
    let excerpt: CodeExcerpt
    let workspace: ReviewWorkspace
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text("\(excerpt.path):\(excerpt.firstLine + 1)")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.head)
                if excerpt.isChanged {
                    Text("Changed")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.2), in: .capsule)
                }
                Spacer()
                if workspace.pullRequest?.file(at: excerpt.path) != nil {
                    Button("Open") {
                        if workspace.open(excerpt) { close() }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(excerpt.lines.enumerated()), id: \.offset) { offset, line in
                    let number = excerpt.firstLine + offset
                    HStack(spacing: 8) {
                        Text("\(number + 1)")
                            .frame(width: 36, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(line.isEmpty ? " " : line)
                            .fontWeight(number == excerpt.focusLine ? .semibold : .regular)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(excerpt.changedLines.contains(number) ? Color.green.opacity(0.14) : .clear)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .padding(6)
            .background(.background.opacity(0.6), in: .rect(cornerRadius: 8))
        }
    }
}

import AppKit
import RiviuAI
import RiviuDiff
import RiviuMarkdown
import RiviuSyntax
import SwiftUI

/// One path through the selected code, read top to bottom like a stack trace: where it starts, the
/// selected function, and what it goes on to call, each step as highlighted code.
struct HotPathPopover: View {
    let target: CodeTarget
    let workspace: ReviewWorkspace
    let settings: AppSettings
    let close: () -> Void

    @State private var hotPath: HotPath?
    @State private var isTracing = true
    /// `hops[i]` describes going from step i to step i + 1. Empty until the AI answers, and if it can't.
    @State private var hops: [String] = []
    @State private var hopsState = HopsState.notAsked
    @State private var explanation: String?
    @State private var isExplaining = false
    @State private var errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    private enum HopsState {
        case notAsked, loading, loaded, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hot Path", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            IndexStatus(workspace: workspace) { index in
                if target.side == .base {
                    Text("The hot path follows the new version of the code. Pick added or unchanged lines.")
                        .font(.callout)
                } else {
                    content
                        .task(id: ObjectIdentifier(index)) { await trace(in: index) }
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: 680)
        .onAppear { workspace.prepareCodeIndex() }
    }

    @ViewBuilder
    private var content: some View {
        if let hotPath {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hotPath.steps.enumerated()), id: \.element.id) { number, step in
                        HotPathStepView(step: step, number: number, path: hotPath, hop: hopText(after: number),
                                        isDescribing: hopsState == .loading, theme: theme, font: settings.editorFont,
                                        lineSpacing: settings.lineSpacing, workspace: workspace, close: close)
                    }
                    if hotPath.steps.count == 1 {
                        Text("Nothing else in the repository calls this code, and it calls nothing worth following.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    if hopsState == .failed {
                        Text("Couldn't describe the steps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    explainSection(hotPath)
                        .padding(.top, 12)
                }
            }
            .frame(maxHeight: 640)
            .fixedSize(horizontal: false, vertical: true)
        } else if isTracing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Tracing the path…")
                    .font(.callout)
            }
        } else {
            Text("This code isn't in or near a function, so there's no path to trace.")
                .font(.callout)
        }
    }

    private var theme: EditorTheme {
        settings.themeFamily.theme(dark: colorScheme == .dark)
    }

    private func hopText(after number: Int) -> String? {
        hops.indices.contains(number) && !hops[number].isEmpty ? hops[number] : nil
    }

    // MARK: - Building the path

    /// Traces the path off the main thread, shows it, then asks the AI to describe each hop.
    private func trace(in index: SymbolIndex) async {
        let finder = HotPathFinder(index: index, changedLines: workspace.changedHeadLinesByPath)
        let path = target.filePath
        let lines = target.lines
        hotPath = await Task.detached { finder.hotPath(path: path, lines: lines) }.value
        isTracing = false
        await describeHops()
    }

    /// One AI request for the whole path. Says nothing if the AI isn't set up, and asks only once per path and commit.
    private func describeHops() async {
        guard let hotPath, hotPath.steps.count > 1, let pullRequest = workspace.pullRequest else { return }
        let key = HotPathHopCache.key(headSHA: pullRequest.headSHA, path: hotPath)
        if let cached = HotPathHopCache.descriptions[key] {
            hops = cached
            hopsState = .loaded
            return
        }
        guard let provider = try? AISetup.makeProvider(for: .explain, settings: settings) else { return }
        hopsState = .loading
        do {
            let reply = try await provider.reply(to: ReviewPrompts.hotPathHopsRequest(path: hotPath, pullRequest: pullRequest))
            let described = try HotPathHops.parse(reply).hops
            HotPathHopCache.descriptions[key] = described
            hops = described
            hopsState = .loaded
        } catch {
            // Closing the popover cancels the request; that isn't worth a message.
            hopsState = Task.isCancelled ? .notAsked : .failed
        }
    }

    // MARK: - Explaining the whole path

    @ViewBuilder
    private func explainSection(_ hotPath: HotPath) -> some View {
        if let explanation {
            StructuredText(markdown: explanation)
                .textual.textSelection(.enabled)
        } else if let errorMessage {
            AIErrorView(message: errorMessage)
        }
        if explanation == nil {
            Button(isExplaining ? "Explaining…" : "Explain This Path", systemImage: "sparkles") {
                explain(hotPath)
            }
            .buttonStyle(.bordered)
            .disabled(isExplaining || hotPath.steps.count < 2)
        }
    }

    private func explain(_ hotPath: HotPath) {
        isExplaining = true
        errorMessage = nil
        // The explanation reads the steps above the selection as callers and the ones below as what it calls.
        func items(_ steps: ArraySlice<HotPathStep>) -> [HotPathItem] {
            steps.map { HotPathItem(function: $0.function, title: $0.title, excerpt: $0.excerpt) }
        }
        let focus = hotPath.focus
        let code = target.code.isEmpty ? focus.excerpt.lines.joined(separator: "\n") : target.code
        Task {
            do {
                explanation = try await workspace.explainHotPath(focus: focus.title, code: code,
                                                                 callers: items(hotPath.steps[..<hotPath.focusIndex]),
                                                                 callees: items(hotPath.steps[(hotPath.focusIndex + 1)...]))
            } catch {
                errorMessage = error.localizedDescription
            }
            isExplaining = false
        }
    }
}

/// One step of the hot path: a dot on the line that joins the steps, the function's name and place, its code,
/// and what happens on the way to the next step.
private struct HotPathStepView: View {
    let step: HotPathStep
    let number: Int
    let path: HotPath
    /// What happens going on to the next step, once the AI has said.
    let hop: String?
    let isDescribing: Bool
    let theme: EditorTheme
    let font: NSFont
    let lineSpacing: LineSpacing
    let workspace: ReviewWorkspace
    let close: () -> Void

    private var isFirst: Bool { number == 0 }
    private var isLast: Bool { number == path.steps.count - 1 }
    private var isFocus: Bool { number == path.focusIndex }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            dot
                .frame(width: 14, height: 20)
            VStack(alignment: .leading, spacing: 6) {
                header
                HotPathCodeView(step: step, isFocus: isFocus, theme: theme, font: font, lineSpacing: lineSpacing)
                if !isLast {
                    hopRow
                        .padding(.vertical, 6)
                }
            }
            .padding(.bottom, isLast ? 0 : 4)
        }
        // The line joining this step to the next runs behind the dots, like a stack trace read top to bottom.
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 1.5)
                    .padding(.top, 20)
                    .offset(x: 6.25)
                    .accessibilityHidden(true)
            }
        }
    }

    private var dot: some View {
        ZStack {
            if isFocus {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 3)
                    .frame(width: 18, height: 18)
            } else {
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 1.5)
                    .background(Circle().fill(.background))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }

    /// "Entry point", "Selected" and "End" where they apply, then the function, where it is, and Open.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if !roles.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(roles, id: \.title) { role in
                            Label(role.title, systemImage: role.symbol)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(role.isFocus ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(step.title)
                        .font(.callout.weight(.semibold).monospaced())
                    Text(step.shortLocation)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(step.function.path)
                    if step.isChanged {
                        Label("Changed", systemImage: "circle.fill")
                            .labelStyle(ChangedLabelStyle())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            if workspace.pullRequest?.file(at: step.function.path) != nil {
                Button("Open") {
                    if workspace.open(step.excerpt) { close() }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Open \(step.title) in the diff")
            }
        }
    }

    private struct Role {
        let title: String
        let symbol: String
        var isFocus = false
    }

    private var roles: [Role] {
        var roles: [Role] = []
        if isFirst && path.steps.count > 1 {
            roles.append(path.hasMoreAbove ? Role(title: "Called from further up", symbol: "ellipsis")
                                           : Role(title: "Entry point", symbol: "arrow.down.to.line"))
        }
        if isFocus {
            roles.append(Role(title: "Selected", symbol: "scope", isFocus: true))
        }
        if isLast && path.steps.count > 1 {
            roles.append(path.hasMoreBelow ? Role(title: "Goes deeper", symbol: "ellipsis")
                                           : Role(title: "End", symbol: "flag.checkered"))
        }
        return roles
    }

    private var accessibilityLabel: String {
        var parts = ["Step \(number + 1) of \(path.steps.count)"]
        parts += roles.map(\.title)
        parts.append("\(step.function.name), \((step.function.path as NSString).lastPathComponent) line \(step.function.lines.lowerBound + 1)")
        if step.isChanged { parts.append("changed in this pull request") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var hopRow: some View {
        if let hop {
            Text(inlineMarkdown: hop)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Then: \(hop)")
        } else if isDescribing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Describing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            // Keeps the steps apart even without a description.
            Color.clear
                .frame(height: 2)
                .accessibilityHidden(true)
        }
    }
}

/// The "Changed" marker: a small dot then the word, so it doesn't rely on color alone.
private struct ChangedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.green)
            configuration.title
        }
    }
}

/// A step's code, highlighted like the diff. Changed lines are tinted with a bar at the start, the call to
/// the next step has a chevron, and the selection is shaded. Long lines scroll sideways instead of being cut off.
private struct HotPathCodeView: View {
    let step: HotPathStep
    let isFocus: Bool
    let theme: EditorTheme
    let font: NSFont
    let lineSpacing: LineSpacing

    /// Each line with its syntax colors, once parsed.
    @State private var highlighted: [AttributedString] = []
    /// The width of the code box, so short lines still tint the whole row.
    @State private var visibleWidth: CGFloat = 0
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// The same height as a row in the diff.
    private var rowHeight: CGFloat {
        ceil(font.ascender - font.descender + font.leading) + lineSpacing.extraHeight
    }

    private var excerpt: CodeExcerpt { step.excerpt }

    var body: some View {
        let lines = dedentedLines
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { offset in
                    codeLine(highlighted.indices.contains(offset) ? highlighted[offset] : plain(lines[offset]),
                             number: excerpt.firstLine + offset)
                }
            }
            .padding(.vertical, 4)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
        .font(Font(font))
        .background(Color(nsColor: theme.background))
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocus ? AnyShapeStyle(Color.accentColor.opacity(0.7)) : AnyShapeStyle(.separator),
                              lineWidth: isFocus ? 1.5 : 1)
        }
        .task(id: "\(excerpt.id):\(excerpt.lines.count):\(theme.name)") {
            highlighted = await highlight(dedentedLines)
        }
    }

    /// One line: a chevron on the call to the next step, the line number, and the code.
    private func codeLine(_ text: AttributedString, number: Int) -> some View {
        let palette = DiffPalette(theme: theme, increaseContrast: colorSchemeContrast == .increased)
        let isChanged = excerpt.changedLines.contains(number)
        let isCall = number == step.callLine
        let isSelected = step.selectedLines?.contains(number) == true
        return HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .opacity(isCall ? 1 : 0)
                .frame(width: 12)
                .accessibilityHidden(true)
            Text("\(number + 1)")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(Color(cgColor: palette.lineNumber))
            Text(text.characters.isEmpty ? AttributedString(" ") : text)
                .fontWeight(isCall ? .semibold : .regular)
                .fixedSize()
                .padding(.leading, 8)
        }
        .frame(height: rowHeight)
        .padding(.trailing, 10)
        // At least as wide as the box, and as wide as the longest line, so every row's tint lines up.
        .frame(minWidth: visibleWidth, maxWidth: .infinity, alignment: .leading)
        .background {
            if isChanged {
                Color(cgColor: palette.addedLine)
            } else if isSelected {
                Color(nsColor: theme.selection).opacity(0.6)
            } else if isCall {
                Color.accentColor.opacity(0.1)
            }
        }
        .overlay(alignment: .leading) {
            if isChanged {
                Rectangle()
                    .fill(Color(cgColor: palette.addedMarker))
                    .frame(width: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue([isCall ? "Calls the next step" : nil, isSelected ? "Selected" : nil,
                             isChanged ? "Changed in this pull request" : nil]
            .compactMap { $0 }.joined(separator: ", "))
    }

    private func plain(_ line: String) -> AttributedString {
        var text = AttributedString(line)
        text.foregroundColor = Color(nsColor: theme.foreground)
        return text
    }

    /// The lines without the indentation they all share, so code nested in a class doesn't start halfway across.
    private var dedentedLines: [String] {
        let indents = excerpt.lines.filter { !$0.allSatisfy(\.isWhitespace) }.map { $0.prefix { $0 == " " || $0 == "\t" }.count }
        let shared = indents.min() ?? 0
        return excerpt.lines.map { String($0.dropFirst(min(shared, $0.prefix { $0 == " " || $0 == "\t" }.count))) }
    }

    /// Parses just these lines, off the main thread. A few lines out of a file don't always parse perfectly,
    /// but they come close.
    private func highlight(_ lines: [String]) async -> [AttributedString] {
        let document = await SyntaxDocument.parse(lines: lines, language: SyntaxLanguage.detect(path: excerpt.path))
        return lines.indices.map { index in
            var text = plain(lines[index])
            let utf16 = lines[index].utf16
            for token in document.tokens(line: index) {
                guard let color = theme.color(for: token.name), token.range.upperBound <= utf16.count,
                      let lower = String.Index(utf16.index(utf16.startIndex, offsetBy: token.range.lowerBound), within: lines[index]),
                      let upper = String.Index(utf16.index(utf16.startIndex, offsetBy: token.range.upperBound), within: lines[index]),
                      let range = Range(lower..<upper, in: text) else { continue }
                text[range].foregroundColor = Color(nsColor: color)
            }
            return text
        }
    }
}

private extension Text {
    /// Inline Markdown like `code` and **bold**; plain text if it doesn't parse.
    init(inlineMarkdown: String) {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        self.init((try? AttributedString(markdown: inlineMarkdown, options: options)) ?? AttributedString(inlineMarkdown))
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
                let finder = HotPathFinder(index: index, changedLines: workspace.changedHeadLinesByPath)
                if definitions.isEmpty {
                    Text("No definition of \(name) found in the repository.")
                        .font(.callout)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(definitions), id: \.self) { definition in
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

/// A few numbered lines of code, with this pull request's changes tinted and marked with a bar.
/// Long lines scroll sideways instead of being cut off.
private struct ExcerptView: View {
    let title: String
    let excerpt: CodeExcerpt
    let workspace: ReviewWorkspace
    let close: () -> Void

    /// The width of the code box, so short excerpts still tint the whole row.
    @State private var visibleWidth: CGFloat = 0

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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(excerpt.lines.enumerated()), id: \.offset) { offset, line in
                        codeLine(line, number: excerpt.firstLine + offset)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
            .font(.system(.caption, design: .monospaced))
            .padding(6)
            .background(.background.opacity(0.6), in: .rect(cornerRadius: 8))
        }
    }

    /// One line: a chevron on the call site, the line number, and the code.
    /// Changed lines have a green bar at the start as well as the tint, so they don't rely on color alone.
    private func codeLine(_ line: String, number: Int) -> some View {
        let isChanged = excerpt.changedLines.contains(number)
        let isFocus = number == excerpt.focusLine
        return HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .opacity(isFocus ? 1 : 0)
                .frame(width: 10)
                .accessibilityHidden(true)
            Text("\(number + 1)")
                .frame(width: 32, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(line.isEmpty ? " " : line)
                .fontWeight(isFocus ? .semibold : .regular)
                .fixedSize()
                .padding(.leading, 4)
        }
        .padding(.vertical, 1)
        .padding(.trailing, 6)
        // At least as wide as the box, and as wide as the longest line, so every row's tint lines up.
        .frame(minWidth: visibleWidth, maxWidth: .infinity, alignment: .leading)
        .background(isChanged ? Color.green.opacity(0.14) : .clear)
        .overlay(alignment: .leading) {
            if isChanged {
                Rectangle()
                    .fill(.green)
                    .frame(width: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue([isFocus ? "Call site" : nil, isChanged ? "Changed in this pull request" : nil]
            .compactMap { $0 }.joined(separator: ", "))
    }
}

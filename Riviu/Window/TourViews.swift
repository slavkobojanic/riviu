import AppKit
import RiviuDiff
import RiviuSyntax
import SwiftUI

/// The guided tour on the overview: a way to plan one, or its stops.
struct TourSection: View {
    let pullRequest: PullRequest
    let workspace: ReviewWorkspace
    let aiReviews: AIReviewStore
    /// Long tours show their first few stops until "Show All" is pressed.
    @State private var isExpanded = false
    private static let collapsedCount = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Guided Tour")
                    .font(.title3.weight(.semibold))
                Spacer()
                if let tour = workspace.tour {
                    Text("\(tour.stops.count) \(tour.stops.count == 1 ? "stop" : "stops")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Start Tour", systemImage: "play.fill") { workspace.startTour() }
                        .buttonStyle(.bordered)
                }
            }
            if let tour = workspace.tour {
                stops(of: tour)
            } else {
                switch aiReviews.tourActivities[pullRequest.reference] {
                case .reviewing:
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Picking the places worth reading…")
                    }
                case let .failed(message):
                    AIErrorView(message: message)
                    generateButton(title: "Try Again")
                default:
                    Text("A short tour of the few places worth reading, in a sensible order, with the rest summed up at the end.")
                    generateButton(title: "Plan a Tour")
                }
            }
        }
    }

    /// The stops as rows in one card, like a grouped list in Settings. A long tour shows its first few, with a row
    /// at the end to show the rest.
    private func stops(of tour: ReviewTour) -> some View {
        // Hiding a single stop isn't worth the extra row.
        let canCollapse = tour.stops.count > Self.collapsedCount + 1
        let shownCount = isExpanded || !canCollapse ? tour.stops.count : Self.collapsedCount
        return VStack(spacing: 0) {
            ForEach(0..<shownCount, id: \.self) { index in
                if index > 0 {
                    Divider()
                        .padding(.leading, StopRow.textInset)
                }
                StopRow(number: index + 1, stop: tour.stops[index]) { workspace.startTour(at: index) }
            }
            if canCollapse {
                Divider()
                Button { setExpanded(!isExpanded) } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show Fewer" : "Show All \(tour.stops.count) Stops")
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .foregroundStyle(.tint)
                    .padding(.leading, StopRow.textInset)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(.rect(cornerRadius: 14))
        .cardBackground()
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            isExpanded = expanded
        }
    }

    private func generateButton(title: String) -> some View {
        Button(title, systemImage: "map") {
            Task { await aiReviews.generateTour(for: pullRequest) }
        }
        .buttonStyle(.bordered)
    }
}

private struct StopRow: View {
    let number: Int
    let stop: TourStop
    let action: () -> Void
    @State private var isHovered = false

    /// Where the title starts, past the number. Dividers between rows start here too.
    static let textInset: CGFloat = 12 + 22 + 12

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(number)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.title)
                        .font(.headline)
                    Text(stop.chapter)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(stop.fileName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Rectangle().fill(isHovered ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - The tour

/// Takes over the diff area while touring: the stops as cards in a vertical carousel, the focused one in the middle.
struct TourCarousel: View {
    let tour: ReviewTour
    let workspace: ReviewWorkspace
    let settings: AppSettings

    @State private var keyMonitor: Any?
    /// The window the tour is shown in, so its keys don't fire in other windows or tabs.
    @State private var window: NSWindow?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The stops, then the closing card.
    private var cardCount: Int { tour.stops.count + 1 }

    /// Moving between cards slides smoothly, or jumps when Reduce Motion is on.
    private var scrollAnimation: Animation? { reduceMotion ? nil : .smooth }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            carousel
            Divider()
            footer
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .background {
            WindowObserver(onAttach: attach, onBecomeKey: {}, onClose: {})
        }
        // The scroll view takes arrow keys before SwiftUI's key handlers see them, so keys are caught on
        // their way into the window instead.
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                MainActor.assumeIsolated { handleKey(event) } ? nil : event
            }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    /// Remembers the window, and takes the arrow keys away from the sidebar list so they move the tour.
    private func attach(to window: NSWindow) {
        self.window = window
        if window.firstResponder is NSTableView { window.makeFirstResponder(nil) }
    }

    private var carousel: some View {
        HStack(spacing: 0) {
            ChapterRail(tour: tour, workspace: workspace)
                .frame(width: 200)
            // GeometryReader sizes from the space it's offered, so the spacers below can't feed back into the
            // window's minimum size (measuring the scroll view's own height did, and looped).
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    // Only ↑ ↓ and Back and Next move between cards. Without vertical scrolling, sideways swipes
                    // scroll the code instead of being taken for a scroll to the next card.
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 32) {
                            // Half a screen of space above and below lets the first and last cards reach the middle.
                            Color.clear.frame(height: geometry.size.height / 2)
                            ForEach(0..<cardCount, id: \.self) { index in
                                card(at: index, maxCodeHeight: max(160, geometry.size.height * 0.5))
                                    .id(index)
                                    .visualEffect { [reduceMotion, isFocused = workspace.tourCardIndex == index] content, geometry in
                                        // With Reduce Motion on, cards out of focus are just dimmed, and don't move.
                                        let distance = reduceMotion ? 0 : Self.distanceFromMiddle(geometry)
                                        let opacity = reduceMotion ? (isFocused ? 1 : 0.5) : 1 - abs(distance) * 0.6
                                        return content
                                            .scaleEffect(1 - abs(distance) * 0.1)
                                            .opacity(opacity)
                                            .blur(radius: abs(distance) * 4)
                                            // Cards away from the middle drift toward it, so they trail behind a little.
                                            .offset(y: -distance * 40)
                                    }
                            }
                            Color.clear.frame(height: geometry.size.height / 2)
                        }
                        .padding(.horizontal, 32)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.never)
                    .scrollDisabled(true)
                    .onChange(of: workspace.tourCardIndex) { _, index in
                        guard let index else { return }
                        withAnimation(scrollAnimation) { proxy.scrollTo(index, anchor: .center) }
                    }
                    // Once the height is known, and whenever it changes, the focused card goes back to the middle.
                    .onChange(of: geometry.size.height, initial: true) {
                        proxy.scrollTo(workspace.tourCardIndex ?? 0, anchor: .center)
                    }
                }
            }
        }
    }

    /// ↑ and ↓ move between cards, Return opens the stop in the diff and Esc ends the tour.
    /// Only while the tour's window is in front with no sheet over it, and not while typing somewhere
    /// like the chat or moving through a list like the sidebar.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.isKeyWindow, window.attachedSheet == nil else { return false }
        // Outline views are table views too.
        if window.firstResponder is NSText || window.firstResponder is NSTableView { return false }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
        case 126: workspace.advanceTour(by: -1) // up arrow
        case 125: workspace.advanceTour(by: 1) // down arrow
        case 36: workspace.openCurrentTourStop() // return
        case 53: workspace.endTour() // escape
        default: return false
        }
        return true
    }

    @ViewBuilder
    private func card(at index: Int, maxCodeHeight: CGFloat) -> some View {
        let isFocused = workspace.tourCardIndex == index
        Group {
            if tour.stops.indices.contains(index) {
                TourStopCard(stop: tour.stops[index], number: index + 1, total: tour.stops.count, isFocused: isFocused,
                             theme: settings.themeFamily.theme(dark: colorScheme == .dark), font: settings.editorFont,
                             lineSpacing: settings.lineSpacing, maxCodeHeight: maxCodeHeight) {
                    workspace.openCurrentTourStop()
                }
            } else {
                TourEndCard(tour: tour, workspace: workspace)
            }
        }
        .frame(maxWidth: 760)
        .allowsHitTesting(isFocused)
        // A card that isn't in focus is brought to the middle when clicked.
        .overlay {
            if !isFocused {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { workspace.focusTourCard(index) }
            }
        }
    }

    /// -1 at the top of the scroll view, 0 in the middle, 1 at the bottom.
    nonisolated private static func distanceFromMiddle(_ geometry: GeometryProxy) -> CGFloat {
        guard let viewport = geometry.bounds(of: .scrollView), viewport.height > 0 else { return 0 }
        let offset = geometry.frame(in: .scrollView).midY - viewport.height / 2
        return min(max(offset / (viewport.height / 2), -1), 1)
    }

    /// A bar above the cards, so End Tour never sits on top of one.
    private var header: some View {
        HStack {
            Label("Guided Tour", systemImage: "map")
                .font(.headline)
            Spacer()
            Button("End Tour", systemImage: "xmark") { workspace.endTour() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Back and Next, in the middle of a bar below the cards. ↑ and ↓ do the same.
    private var footer: some View {
        let index = workspace.tourCardIndex ?? 0
        return HStack(spacing: 12) {
            Button("Back", systemImage: "chevron.up") { workspace.advanceTour(by: -1) }
                .disabled(index == 0)
                .help("Previous stop (↑)")
            Button("Next", systemImage: "chevron.down") { workspace.advanceTour(by: 1) }
                .disabled(index >= cardCount - 1)
                .help("Next stop (↓)")
        }
        .buttonStyle(.bordered)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The chapters down the side, each with its stops underneath, like the contents of a docs page.
/// The stop in focus is marked; clicking a chapter or a stop goes there.
private struct ChapterRail: View {
    let tour: ReviewTour
    let workspace: ReviewWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(tour.chapters, id: \.self) { chapter in
                VStack(alignment: .leading, spacing: 6) {
                    Button(chapter) {
                        if let first = tour.stops.firstIndex(where: { $0.chapter == chapter }) {
                            workspace.focusTourCard(first)
                        }
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(workspace.currentTourStop?.chapter == chapter ? .primary : .secondary)
                    ForEach(tour.stops.indices.filter { tour.stops[$0].chapter == chapter }, id: \.self) { index in
                        stopLink(index)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .multilineTextAlignment(.leading)
        .padding(.leading, 24)
        .padding(.trailing, 8)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func stopLink(_ index: Int) -> some View {
        let isCurrent = workspace.tourCardIndex == index
        return Button { workspace.focusTourCard(index) } label: {
            HStack(spacing: 8) {
                Capsule()
                    .fill(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 2)
                Text(tour.stops[index].title)
                    .font(.caption)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .padding(.vertical, 2)
            }
            // Keeps the marker as tall as the title; on its own it would stretch to fill the rail.
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(.rect)
        }
    }
}

/// One stop: why it matters, and the lines it's about.
private struct TourStopCard: View {
    let stop: TourStop
    let number: Int
    let total: Int
    let isFocused: Bool
    let theme: EditorTheme
    let font: NSFont
    let lineSpacing: LineSpacing
    let maxCodeHeight: CGFloat
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(stop.title)
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(number) of \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(markdown: stop.explanation)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            TourExcerptView(stop: stop, theme: theme, font: font, lineSpacing: lineSpacing, maxHeight: maxCodeHeight, open: open)
        }
        .padding(22)
        .cardBackground(isFocused: isFocused)
    }
}

/// The diff of a stop's lines, highlighted like the diff view.
private struct TourExcerptView: View {
    let stop: TourStop
    let theme: EditorTheme
    let font: NSFont
    let lineSpacing: LineSpacing
    /// Longer excerpts scroll up and down inside the card, since the tour itself doesn't scroll.
    let maxHeight: CGFloat
    let open: () -> Void

    /// Each line with its syntax colors, once parsed.
    @State private var highlighted: [AttributedString] = []
    /// How wide the code area is, so the added and removed colors reach its edge even on short lines.
    @State private var visibleWidth: CGFloat = 0
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var isTall: Bool { CGFloat(stop.excerpt.count) * rowHeight > maxHeight }

    /// The same height as a row in the diff.
    private var rowHeight: CGFloat {
        ceil(font.ascender - font.descender + font.leading) + lineSpacing.extraHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(stop.filePath)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.head)
                Text("lines \(stop.lines.lowerBound)–\(stop.lines.upperBound)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open in Diff", systemImage: "arrow.up.forward", action: open)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            // Long lines scroll sideways, all together, instead of being cut off.
            ScrollView(isTall ? [.horizontal, .vertical] : .horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stop.excerpt.enumerated()), id: \.offset) { index, line in
                        ExcerptLine(line: line, text: highlighted.indices.contains(index) ? highlighted[index] : AttributedString(lines[index]),
                                    theme: theme, height: rowHeight)
                    }
                }
                .padding(.trailing, 12)
                .frame(minWidth: visibleWidth, alignment: .leading)
                // The colors sit behind the rows as one layer, so every row's color is as wide as the longest line.
                .background(alignment: .top) {
                    VStack(spacing: 0) {
                        ForEach(Array(stop.excerpt.enumerated()), id: \.offset) { _, line in
                            Rectangle()
                                .fill(tint(for: line.kind))
                                .frame(height: rowHeight)
                        }
                    }
                }
            }
            .frame(height: isTall ? maxHeight : nil)
            // The tour turns scrolling off for its cards; the code scrolls anyway.
            .scrollDisabled(false)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
            .font(Font(font))
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: theme.background))
        .clipShape(.rect(cornerRadius: 10))
        .task(id: "\(stop.filePath):\(stop.lines):\(theme.name)") {
            highlighted = await highlight()
        }
    }

    /// The lines without the indentation they all share, so deeply nested code doesn't start halfway across.
    private var lines: [String] {
        let texts = stop.excerpt.map(\.text)
        let indents = texts.filter { !$0.allSatisfy(\.isWhitespace) }.map { $0.prefix { $0 == " " || $0 == "\t" }.count }
        let shared = indents.min() ?? 0
        return texts.map { String($0.dropFirst(min(shared, $0.prefix { $0 == " " || $0 == "\t" }.count))) }
    }

    /// The color behind an added or removed line, like in the diff.
    private func tint(for kind: PatchExcerpt.Line.Kind) -> Color {
        let palette = DiffPalette(theme: theme, increaseContrast: colorSchemeContrast == .increased)
        return switch kind {
        case .added: Color(cgColor: palette.addedLine)
        case .removed: Color(cgColor: palette.removedLine)
        case .context: .clear
        }
    }

    /// Parses just these lines. A few lines out of a file don't always parse perfectly, but they come close.
    private func highlight() async -> [AttributedString] {
        let lines = lines
        let document = await SyntaxDocument.parse(lines: lines, language: SyntaxLanguage.detect(path: stop.filePath))
        return lines.indices.map { index in
            var text = AttributedString(lines[index])
            text.foregroundColor = Color(nsColor: theme.foreground)
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

private struct ExcerptLine: View {
    let line: PatchExcerpt.Line
    let text: AttributedString
    let theme: EditorTheme
    /// The height of a row in the diff, with the editor's line spacing.
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(number.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(Color(nsColor: theme.lineNumber))
            Text(marker)
                .frame(width: 22)
                .foregroundStyle(Color(nsColor: theme.lineNumber))
            Text(text.characters.isEmpty ? AttributedString(" ") : text)
                .fixedSize()
        }
        .frame(height: height)
    }

    private var number: Int? { line.newNumber ?? line.oldNumber }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .context: ""
        }
    }
}

/// The last card: what the tour left out, and what to do next.
private struct TourEndCard: View {
    let tour: ReviewTour
    let workspace: ReviewWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("That's the tour")
                .font(.title2.weight(.semibold))
            if !tour.rest.isEmpty {
                Text(markdown: tour.rest)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Start Over", systemImage: "arrow.counterclockwise") { workspace.focusTourCard(0) }
                    .buttonStyle(.bordered)
                Button("End Tour") { workspace.endTour() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(isFocused: workspace.tourCardIndex == tour.stops.count)
    }
}

/// Floats over the diff while looking at a stop, to get back to the tour.
struct BackToTourBar: View {
    let workspace: ReviewWorkspace

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button("Back to Tour", systemImage: "chevron.backward") { workspace.returnToTour() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.glassProminent)
                Button("End Tour", systemImage: "xmark") { workspace.endTour() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
            .controlSize(.large)
        }
    }
}

private extension View {
    /// The shadow goes on the card's shape only: on the card itself it would also shadow everything inside it.
    func cardBackground(isFocused: Bool) -> some View {
        background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.background)
                .shadow(color: .black.opacity(isFocused ? 0.14 : 0.05), radius: isFocused ? 20 : 6, y: 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.separator))
    }
}

private extension Text {
    /// Inline Markdown like `code` and **bold**; plain text if it doesn't parse.
    init(markdown: String) {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            self.init(attributed)
        } else {
            self.init(verbatim: markdown)
        }
    }
}

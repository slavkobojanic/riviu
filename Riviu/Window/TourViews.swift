import RiviuDiff
import SwiftUI

/// The guided tour on the overview: a way to plan one, or its stops.
struct TourSection: View {
    let pullRequest: PullRequest
    let workspace: ReviewWorkspace
    let aiReviews: AIReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Guided Tour")
                    .font(.title3.weight(.semibold))
                Spacer()
                if let tour = workspace.tour {
                    Text("\(tour.stops.count) \(tour.stops.count == 1 ? "stop" : "stops")")
                        .font(.caption)
                    Button("Start Tour", systemImage: "play.fill") { workspace.startTour() }
                        .buttonStyle(.borderedProminent)
                }
            }
            if let tour = workspace.tour {
                ForEach(Array(tour.stops.enumerated()), id: \.offset) { index, stop in
                    StopRow(number: index + 1, stop: stop) { workspace.startTour(at: index) }
                }
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
    let start: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: start) {
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
            .background(.fill.opacity(isHovered ? 0.9 : 0.5), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Start the tour here")
    }
}

// MARK: - The tour

/// Takes over the diff area while touring: the stops as cards in a vertical carousel, the focused one in the middle.
struct TourCarousel: View {
    let tour: ReviewTour
    let workspace: ReviewWorkspace

    /// Each card's vertical center in the scroll view, to find the one nearest the middle.
    @State private var cardCenters: [Int: CGFloat] = [:]
    @FocusState private var isFocused: Bool

    /// The stops, then the closing card.
    private var cardCount: Int { tour.stops.count + 1 }

    var body: some View {
        HStack(spacing: 0) {
            ChapterRail(tour: tour, workspace: workspace)
                .frame(width: 200)
            // GeometryReader sizes from the space it's offered, so the spacers below can't feed back into the
            // window's minimum size (measuring the scroll view's own height did, and looped).
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 32) {
                            // Half a screen of space above and below lets the first and last cards reach the middle.
                            Color.clear.frame(height: geometry.size.height / 2)
                            ForEach(0..<cardCount, id: \.self) { index in
                                card(at: index)
                                    .id(index)
                                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).midY } action: {
                                        cardCenters[index] = $0
                                    }
                                    .visualEffect { content, geometry in
                                        let distance = Self.distanceFromMiddle(geometry)
                                        return content
                                            .scaleEffect(1 - abs(distance) * 0.1)
                                            .opacity(1 - abs(distance) * 0.6)
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
                    .onScrollPhaseChange { _, phase in
                        if phase == .idle { snapToNearestCard(proxy, middle: geometry.size.height / 2) }
                    }
                    .onChange(of: workspace.tourCardIndex) { _, index in
                        guard let index else { return }
                        withAnimation(.smooth) { proxy.scrollTo(index, anchor: .center) }
                    }
                    // Once the height is known, and whenever it changes, the focused card goes back to the middle.
                    .onChange(of: geometry.size.height, initial: true) {
                        proxy.scrollTo(workspace.tourCardIndex ?? 0, anchor: .center)
                    }
                    .onAppear { isFocused = true }
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .top) { header }
        .overlay(alignment: .bottom) { keyHints }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { workspace.advanceTour(by: -1); return .handled }
        .onKeyPress(.downArrow) { workspace.advanceTour(by: 1); return .handled }
        .onKeyPress(.return) { workspace.openCurrentTourStop(); return .handled }
        .onKeyPress(.escape) { workspace.endTour(); return .handled }
    }

    @ViewBuilder
    private func card(at index: Int) -> some View {
        let isFocused = workspace.tourCardIndex == index
        Group {
            if tour.stops.indices.contains(index) {
                TourStopCard(stop: tour.stops[index], number: index + 1, total: tour.stops.count, isFocused: isFocused) {
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

    /// When scrolling stops, the card nearest the middle comes into focus and moves to the exact middle.
    private func snapToNearestCard(_ proxy: ScrollViewProxy, middle: CGFloat) {
        guard let nearest = cardCenters.min(by: { abs($0.value - middle) < abs($1.value - middle) })?.key else { return }
        if nearest != workspace.tourCardIndex {
            workspace.focusTourCard(nearest) // moves it to the middle through onChange
        } else if abs((cardCenters[nearest] ?? middle) - middle) > 2 {
            withAnimation(.smooth) { proxy.scrollTo(nearest, anchor: .center) }
        }
    }

    private var header: some View {
        HStack {
            Label("Guided Tour", systemImage: "map")
                .font(.headline)
            Spacer()
            Button("End Tour", systemImage: "xmark") { workspace.endTour() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var keyHints: some View {
        Text("↑ ↓ to move    ↩ open in the diff    esc to end the tour")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
    }
}

/// The chapters down the side, with the current one marked. Clicking one jumps to its first stop.
private struct ChapterRail: View {
    let tour: ReviewTour
    let workspace: ReviewWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(tour.chapters, id: \.self) { chapter in
                let isCurrent = workspace.currentTourStop?.chapter == chapter
                Button {
                    if let first = tour.stops.firstIndex(where: { $0.chapter == chapter }) {
                        workspace.focusTourCard(first)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            .frame(width: 8, height: 8)
                        Text(chapter)
                            .font(.callout.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? .primary : .secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 24)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

/// One stop: why it matters, and the lines it's about.
private struct TourStopCard: View {
    let stop: TourStop
    let number: Int
    let total: Int
    let isFocused: Bool
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(stop.chapter.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(number) of \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(stop.title)
                .font(.title2.weight(.semibold))
            Text(markdown: stop.explanation)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            TourExcerptView(stop: stop, open: open)
        }
        .padding(22)
        .cardBackground(isFocused: isFocused)
    }
}

/// The diff of a stop's lines.
private struct TourExcerptView: View {
    let stop: TourStop
    let open: () -> Void

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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stop.excerpt.enumerated()), id: \.offset) { _, line in
                    ExcerptLine(line: line)
                }
            }
            .padding(.vertical, 4)
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 10))
        .clipShape(.rect(cornerRadius: 10))
    }
}

private struct ExcerptLine: View {
    let line: PatchExcerpt.Line

    var body: some View {
        HStack(spacing: 0) {
            Text(number.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(marker)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(line.text.isEmpty ? " " : line.text)
                .lineLimit(1)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
    }

    private var number: Int? { line.newNumber ?? line.oldNumber }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .context: ""
        }
    }

    private var tint: Color {
        switch line.kind {
        case .added: Color.green.opacity(0.14)
        case .removed: Color.red.opacity(0.12)
        case .context: .clear
        }
    }
}

/// The last card: what the tour left out, and what to do next.
private struct TourEndCard: View {
    let tour: ReviewTour
    let workspace: ReviewWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THE REST")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("That's the tour")
                .font(.title2.weight(.semibold))
            if !tour.rest.isEmpty {
                Text(markdown: tour.rest)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if tour.skippedFileCount > 0 {
                Text("The tour doesn't stop in \(tour.skippedFileCount) of the changed files. They're in the sidebar when you want them.")
                    .foregroundStyle(.secondary)
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
    func cardBackground(isFocused: Bool) -> some View {
        background(.background, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.separator))
            .shadow(color: .black.opacity(isFocused ? 0.14 : 0.05), radius: isFocused ? 20 : 6, y: 6)
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

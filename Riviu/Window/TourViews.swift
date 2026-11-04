import SwiftUI

/// The guided tour on the overview: a way to start one, or its chapters.
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
                    Text("\(tour.chapters.count) chapters  \(tour.stopCount) stops")
                        .font(.caption)
                    Button("Start Tour", systemImage: "play.fill") { workspace.startTour() }
                        .buttonStyle(.borderedProminent)
                }
            }
            if let tour = workspace.tour {
                ForEach(Array(tour.chapters.enumerated()), id: \.offset) { index, chapter in
                    ChapterRow(number: index + 1, chapter: chapter) { workspace.startTour(atChapter: index) }
                }
            } else {
                switch aiReviews.tourActivities[pullRequest.reference] {
                case .reviewing:
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Planning a reading order…")
                    }
                case let .failed(message):
                    AIErrorView(message: message)
                    generateButton(title: "Try Again")
                default:
                    Text("Read the changes in an order that makes sense: the core change first, then its callers, then tests, with small stuff at the end.")
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

private struct ChapterRow: View {
    let number: Int
    let chapter: TourChapter
    let start: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: start) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(chapter.isNotCovered ? "!" : "\(number)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 22)
                    .foregroundStyle(chapter.isNotCovered ? .statusOrange : .primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(.headline)
                    Text(chapter.why)
                        .font(.callout)
                }
                Spacer(minLength: 8)
                Text("\(chapter.stops.count) \(chapter.stops.count == 1 ? "stop" : "stops")")
                    .font(.caption)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.opacity(isHovered ? 0.9 : 0.5), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Start the tour at this chapter")
    }
}

/// Floats over the diff while touring: the chapter, why it matters, and Previous / Next.
struct TourBar: View {
    let tour: ReviewTour
    let position: TourPosition
    let workspace: ReviewWorkspace

    private var chapter: TourChapter { tour.chapters[position.chapter] }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: chapter.isNotCovered ? "exclamationmark.triangle" : "map")
                .font(.title3)
                .foregroundStyle(chapter.isNotCovered ? .statusOrange : .accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Chapter \(position.chapter + 1) of \(tour.chapters.count)  \(chapter.title)")
                    .font(.headline)
                Text(chapter.why)
                    .font(.callout)
                    .lineLimit(2)
                Text("Stop \(workspace.tourStopNumber ?? 1) of \(tour.stopCount)  \((workspace.currentTourStop?.filePath as NSString?)?.lastPathComponent ?? "")")
                    .font(.caption)
            }
            Spacer(minLength: 8)
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button("Previous", systemImage: "chevron.left") { workspace.advanceTour(by: -1) }
                        .disabled(workspace.tourStopNumber == 1)
                        .help("Previous stop (⌥⌘←)")
                    Button("Next", systemImage: "chevron.right") { workspace.advanceTour(by: 1) }
                        .disabled(workspace.tourStopNumber == tour.stopCount)
                        .help("Next stop (⌥⌘→)")
                    Button("End Tour", systemImage: "xmark") { workspace.endTour() }
                        .help("End the tour")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(maxWidth: 720)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

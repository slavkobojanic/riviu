import RiviuDiff
import RiviuGitHub
import RiviuMarkdown
import SwiftUI

/// CI checks on the reviewed commit. Failed GitHub Actions jobs can be explained by the AI.
struct ChecksSection: View {
    let workspace: ReviewWorkspace
    @State private var showsFinished = false

    /// Failed and running checks are always listed. Finished ones (passed, skipped…) are folded into one counted row.
    private var failing: [GitHubCheckRun] { workspace.checkRuns.filter(\.isFailure) }
    private var running: [GitHubCheckRun] { workspace.checkRuns.filter(\.isRunning) }
    private var finished: [GitHubCheckRun] { workspace.checkRuns.filter { !$0.isFailure && !$0.isRunning } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Checks")
                    .font(.title3.weight(.semibold))
                ChecksSummaryLabel(checkRuns: workspace.checkRuns)
            }
            ForEach(failing) { run in
                FailedCheckRow(run: run, workspace: workspace)
            }
            ForEach(running) { run in
                CheckRow(run: run)
            }
            if !finished.isEmpty {
                FinishedChecksRow(checkRuns: finished, isExpanded: $showsFinished)
                if showsFinished {
                    ForEach(finished) { run in
                        CheckRow(run: run)
                            .padding(.leading, 26)
                    }
                }
            }
        }
    }
}

/// "12 passed, 2 skipped", with a button to list them.
private struct FinishedChecksRow: View {
    let checkRuns: [GitHubCheckRun]
    @Binding var isExpanded: Bool

    /// Counts by conclusion, most common first: "12 passed, 2 skipped".
    private var summary: String {
        let counts = Dictionary(grouping: checkRuns) { run in
            run.conclusion == "success" ? "passed" : (run.conclusion ?? "done").replacingOccurrences(of: "_", with: " ")
        }
        return counts.sorted { $0.value.count > $1.value.count }
            .map { "\($0.value.count) \($0.key)" }
            .joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            if checkRuns.contains(where: { $0.conclusion == "success" }) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.statusGreen)
            } else {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            Text(summary)
            Spacer()
            Button(isExpanded ? "Hide" : "Show All") { isExpanded.toggle() }
                .buttonStyle(.borderless)
        }
    }
}

/// "3 failing", "12 passed" or "2 running", for the sidebar header and the Checks section.
struct ChecksSummaryLabel: View {
    let checkRuns: [GitHubCheckRun]

    var body: some View {
        let failing = checkRuns.filter(\.isFailure).count
        let running = checkRuns.filter(\.isRunning).count
        Group {
            if checkRuns.isEmpty {
                EmptyView()
            } else if failing > 0 {
                Label("\(failing) failing", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.statusRed)
            } else if running > 0 {
                Label("\(running) running", systemImage: "clock")
                    .foregroundStyle(.statusOrange)
            } else {
                Label("Checks passed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.statusGreen)
            }
        }
        .font(.caption)
        .help("CI checks on the reviewed commit")
    }
}

private struct CheckRow: View {
    let run: GitHubCheckRun

    var body: some View {
        HStack(spacing: 10) {
            CheckStatusIcon(run: run)
            Text(run.name)
            Spacer()
            Text(run.isRunning ? "Running" : (run.conclusion ?? "").replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let url = run.htmlUrl {
                OpenOnGitHubLink(url: url)
            }
        }
    }
}

private struct FailedCheckRow: View {
    let run: GitHubCheckRun
    let workspace: ReviewWorkspace
    @State private var explanation: FailureExplanation?
    @State private var isExplaining = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CheckStatusIcon(run: run)
                Text(run.name)
                    .font(.headline)
                Spacer()
                if run.hasLogs && explanation == nil {
                    Button(isExplaining ? "Reading the log…" : "Explain Failure", systemImage: "sparkles", action: explain)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isExplaining)
                        .help("Ask the AI what broke, from the end of the job's log and the diff")
                }
                if let url = run.htmlUrl {
                    OpenOnGitHubLink(url: url)
                }
            }
            if let explanation {
                StructuredText(markdown: explanation.markdown)
                    .textual.textSelection(.enabled)
                if let path = explanation.suspectPath, let line = explanation.suspectLineIndex {
                    Button("Show \((path as NSString).lastPathComponent), line \(line + 1)", systemImage: "scope") {
                        workspace.reveal(lineIndex: line, on: .head, inFileAt: path)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if let errorMessage {
                AIErrorView(message: errorMessage)
            }
        }
        .padding(14)
        .cardBackground(tint: .red)
    }

    private func explain() {
        isExplaining = true
        errorMessage = nil
        Task {
            do {
                explanation = try await workspace.explainFailure(of: run)
            } catch {
                errorMessage = error.localizedDescription
            }
            isExplaining = false
        }
    }
}

/// A small icon link to the check on GitHub, with a hit area big enough to click easily.
private struct OpenOnGitHubLink: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            Label("Open on GitHub", systemImage: "arrow.up.right.square")
                .labelStyle(.iconOnly)
                .frame(minWidth: 20, minHeight: 20)
                .contentShape(.rect)
        }
        .help("Open on GitHub")
    }
}

private struct CheckStatusIcon: View {
    let run: GitHubCheckRun

    var body: some View {
        if run.isRunning {
            ProgressView()
                .controlSize(.mini)
        } else if run.isFailure {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.statusRed)
        } else if run.conclusion == "success" {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.statusGreen)
        } else {
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        }
    }
}

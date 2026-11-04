import RiviuDiff
import RiviuGitHub
import RiviuMarkdown
import SwiftUI

/// CI checks on the reviewed commit. Failed GitHub Actions jobs can be explained by the AI.
struct ChecksSection: View {
    let workspace: ReviewWorkspace
    @State private var showsPassing = false

    private var failing: [GitHubCheckRun] { workspace.checkRuns.filter(\.isFailure) }
    private var others: [GitHubCheckRun] { workspace.checkRuns.filter { !$0.isFailure } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Checks")
                    .font(.title3.weight(.semibold))
                ChecksSummaryLabel(checkRuns: workspace.checkRuns)
                Spacer()
                if !others.isEmpty {
                    Button(showsPassing ? "Hide Others" : "Show All \(workspace.checkRuns.count)") { showsPassing.toggle() }
                        .buttonStyle(.borderless)
                }
            }
            ForEach(failing) { run in
                FailedCheckRow(run: run, workspace: workspace)
            }
            if showsPassing || failing.isEmpty {
                ForEach(others) { run in
                    CheckRow(run: run)
                }
            }
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
                    .foregroundStyle(.red)
            } else if running > 0 {
                Label("\(running) running", systemImage: "clock")
                    .foregroundStyle(.orange)
            } else {
                Label("Checks passed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
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
            if let url = run.htmlUrl {
                Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                    .help("Open on GitHub")
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
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(isExplaining)
                        .help("Ask the AI what broke, from the end of the job's log and the diff")
                }
                if let url = run.htmlUrl {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                        .help("Open on GitHub")
                }
            }
            if let explanation {
                StructuredText(markdown: explanation.markdown)
                    .textual.textSelection(.enabled)
                if let path = explanation.suspectPath, let line = explanation.suspectLineIndex {
                    Button("Show \((path as NSString).lastPathComponent), line \(line + 1)", systemImage: "scope") {
                        workspace.reveal(lineIndex: line, on: .head, inFileAt: path)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
            if let errorMessage {
                AIErrorView(message: errorMessage)
            }
        }
        .padding(14)
        .background(.red.opacity(0.08), in: .rect(cornerRadius: 14))
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

private struct CheckStatusIcon: View {
    let run: GitHubCheckRun

    var body: some View {
        if run.isRunning {
            ProgressView()
                .controlSize(.mini)
        } else if run.isFailure {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else if run.conclusion == "success" {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        }
    }
}

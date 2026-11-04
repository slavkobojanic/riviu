#if DEBUG
import Foundation
import RiviuDiff

/// Launch arguments for jumping straight to a pull request while developing, like
/// `Riviu -debugOpen demo#471 -debugFile services/webhook/handler.go -debugLine 40`.
/// `-debugReviewer login` pretends to be someone else for "since your last review", and
/// `-debugSinceReview YES` turns it on.
enum DebugLaunch {
    static func run(workspace: ReviewWorkspace, account: GitHubAccount) {
        let arguments = UserDefaults.standard
        guard let id = arguments.string(forKey: "debugOpen"), let hash = id.lastIndex(of: "#"),
              let number = Int(id[id.index(after: hash)...]) else { return }
        let reference = PullRequestReference(repository: String(id[..<hash]), number: number)
        Task {
            while !reference.isDemo && !account.isSignedIn {
                try? await Task.sleep(for: .milliseconds(100))
            }
            workspace.open(reference)
            if arguments.bool(forKey: "debugSinceReview") {
                while workspace.sinceLastReview == nil {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                workspace.setShowsChangesSinceLastReview(true)
            }
            guard let path = arguments.string(forKey: "debugFile") else { return }
            while workspace.pullRequest == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let line = arguments.integer(forKey: "debugLine")
            workspace.reveal(lineIndex: max(0, line - 1), on: .head, inFileAt: path)
        }
    }
}
#endif

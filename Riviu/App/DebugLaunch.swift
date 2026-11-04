#if DEBUG
import Foundation

/// Launch arguments for jumping straight to a pull request while developing, like
/// `Riviu -debugOpen demo#471 -debugFile services/webhook/handler.go`.
enum DebugLaunch {
    static func run(workspace: ReviewWorkspace) {
        let arguments = UserDefaults.standard
        guard let id = arguments.string(forKey: "debugOpen"), let hash = id.lastIndex(of: "#"),
              let number = Int(id[id.index(after: hash)...]) else { return }
        workspace.open(PullRequestReference(repository: String(id[..<hash]), number: number))
        guard let path = arguments.string(forKey: "debugFile") else { return }
        Task {
            while workspace.pullRequest == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            workspace.selectFile(at: path)
        }
    }
}
#endif

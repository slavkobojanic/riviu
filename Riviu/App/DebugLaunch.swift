#if DEBUG
import AppKit
import RiviuDiff
import SwiftUI

/// Launch arguments for jumping straight to a pull request while developing, like
/// `Riviu -debugOpen owner/repo#123 -debugFile Sources/App.swift -debugLine 40`.
/// `-debugReviewer login` pretends to be someone else for "since your last review", and
/// `-debugSinceReview YES` turns it on. `-debugHotPath YES` opens the hot path of `-debugLine` in a panel. `-debugTour YES` plans a guided tour with the AI and starts it.
/// `-debugAlsoOpen owner/repo#124` opens a second pull request in a new tab.
enum DebugLaunch {
    /// Keeps the panel alive.
    private static var panel: NSPanel?

    private static func showHotPath(path: String, line: Int, workspace: ReviewWorkspace) {
        let target = CodeTarget(filePath: path, side: .head, lines: line...line, code: "")
        let panel = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 660, height: 700), styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: false)
        panel.title = "Hot Path (debug)"
        panel.contentView = NSHostingView(rootView: HotPathPopover(target: target, workspace: workspace) {})
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    static func run(tabs: ReviewTabs, account: GitHubAccount, aiReviews: AIReviewStore) {
        let arguments = UserDefaults.standard
        guard let id = arguments.string(forKey: "debugOpen"), let reference = PullRequestReference(id: id) else { return }
        Task {
            while !account.isSignedIn || tabs.frontmost == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            tabs.open(reference)
            guard let workspace = tabs.workspace(showing: reference) else { return }
            if let other = arguments.string(forKey: "debugAlsoOpen").flatMap(PullRequestReference.init(id:)) {
                try? await Task.sleep(for: .seconds(1))
                tabs.open(other)
            }
            if arguments.bool(forKey: "debugTour") {
                while workspace.pullRequest == nil {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if let pullRequest = workspace.pullRequest, workspace.tour == nil {
                    await aiReviews.generateTour(for: pullRequest)
                }
                workspace.startTour()
            }
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
            if arguments.bool(forKey: "debugHotPath") {
                showHotPath(path: path, line: max(0, line - 1), workspace: workspace)
            }
        }
    }
}
#endif

import AppKit
import Observation
import SwiftUI

/// The open tabs, so several pull requests can be open at once. Each tab is a window in one native tab group
/// (like Safari's), with its own workspace.
///
/// It also opens windows for places outside them, like the menu bar or a notification. In menu bar mode Riviu
/// leaves the Dock when the last tab closes, and comes back when one opens.
@Observable
final class ReviewTabs {
    static let windowID = "review"

    private struct Tab {
        let workspace: ReviewWorkspace
        weak var window: NSWindow?
    }

    private var tabs: [Tab] = []
    /// The tab in front, which the menus act on.
    private(set) var frontmost: ReviewWorkspace?
    /// Used by the menus while no window is open, so they always have a workspace to point at.
    let placeholder: ReviewWorkspace

    /// Workspaces made for windows that are about to open, already loading their pull request.
    @ObservationIgnored private var waiting: [ReviewWorkspace] = []
    @ObservationIgnored private var openWindow: OpenWindowAction?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let makeWorkspace: () -> ReviewWorkspace

    init(settings: AppSettings, makeWorkspace: @escaping () -> ReviewWorkspace) {
        self.settings = settings
        self.makeWorkspace = makeWorkspace
        placeholder = makeWorkspace()
    }

    /// The frontmost tab's workspace, or the placeholder when no window is open.
    var current: ReviewWorkspace { frontmost ?? placeholder }

    /// The tab showing a pull request, if one is.
    func workspace(showing reference: PullRequestReference) -> ReviewWorkspace? {
        tabs.first { Self.reference(in: $0.workspace) == reference }?.workspace
    }

    /// Any view's `openWindow` action, since this class has no environment of its own.
    func remember(_ action: OpenWindowAction) {
        openWindow = action
    }

    // MARK: - Opening

    /// Switches to the tab showing this pull request, or opens it in a new tab.
    /// An empty tab in front is used instead of opening another one.
    func open(_ reference: PullRequestReference) {
        if let tab = tabs.first(where: { Self.reference(in: $0.workspace) == reference }), let window = tab.window {
            bringForward(window)
            return
        }
        if let front = frontmost, Self.reference(in: front) == nil, let window = tabs.first(where: { $0.workspace === front })?.window {
            front.open(reference)
            bringForward(window)
            return
        }
        let workspace = makeWorkspace()
        workspace.open(reference)
        openTab(with: workspace)
    }

    /// A new tab showing the pull request list.
    func openNewTab() {
        openTab(with: makeWorkspace())
    }

    /// Brings Riviu's window forward, opening one if none is open.
    func show() {
        if let window = tabs.first(where: { $0.workspace === frontmost })?.window ?? tabs.last?.window {
            bringForward(window)
        } else {
            openTab(with: makeWorkspace())
        }
    }

    private func openTab(with workspace: ReviewWorkspace) {
        waiting.append(workspace)
        NSApp.setActivationPolicy(.regular)
        openWindow?(id: Self.windowID)
        NSApp.activate()
    }

    private func bringForward(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Called by each tab's window

    /// The workspace for a window that just opened: the one made for it, or a new one.
    func workspaceForNewWindow() -> ReviewWorkspace {
        waiting.isEmpty ? makeWorkspace() : waiting.removeFirst()
    }

    /// Puts a new window into the tab group of the others, so it opens as a tab rather than a separate window.
    func register(_ workspace: ReviewWorkspace, window: NSWindow) {
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.windowID
        let others = tabs.compactMap(\.window).filter { $0 !== window && $0.isVisible }
        if let other = others.last, !(other.tabbedWindows ?? []).contains(window) {
            other.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        }
        tabs.removeAll { $0.workspace === workspace || $0.window == nil }
        tabs.append(Tab(workspace: workspace, window: window))
        frontmost = workspace
    }

    func didBecomeKey(_ workspace: ReviewWorkspace) {
        frontmost = workspace
    }

    func didClose(_ workspace: ReviewWorkspace) {
        tabs.removeAll { $0.workspace === workspace || $0.window == nil }
        if frontmost === workspace {
            frontmost = tabs.last?.workspace
        }
        if tabs.isEmpty && settings.keepsRunningInMenuBar {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// The pull request a workspace shows or is loading.
    private static func reference(in workspace: ReviewWorkspace) -> PullRequestReference? {
        workspace.pullRequest?.reference ?? workspace.loadingReference
    }
}

/// Decides whether closing the last window quits Riviu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set when the first window appears.
    var settings: AppSettings?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(settings?.keepsRunningInMenuBar ?? false)
    }
}

/// Tells a tab which window it's in, when that window comes to the front, and when it closes.
/// (A tab hidden behind another one isn't closed, though SwiftUI may say it disappeared.)
struct WindowObserver: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void
    let onBecomeKey: () -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        ObservingView(onAttach: onAttach, onBecomeKey: onBecomeKey, onClose: onClose)
    }

    func updateNSView(_ view: ObservingView, context: Context) {}

    final class ObservingView: NSView {
        private let onAttach: (NSWindow) -> Void
        private let onBecomeKey: () -> Void
        private let onClose: () -> Void
        private var observers: [NSObjectProtocol] = []

        init(onAttach: @escaping (NSWindow) -> Void, onBecomeKey: @escaping () -> Void, onClose: @escaping () -> Void) {
            self.onAttach = onAttach
            self.onBecomeKey = onBecomeKey
            self.onClose = onClose
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            onAttach(window)
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onBecomeKey() }
            })
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose() }
            })
        }
    }
}

extension PullRequestReference {
    /// Reads "owner/name#123".
    init?(id: String) {
        guard let hash = id.lastIndex(of: "#"), let number = Int(id[id.index(after: hash)...]) else { return nil }
        self.init(repository: String(id[..<hash]), number: number)
    }
}

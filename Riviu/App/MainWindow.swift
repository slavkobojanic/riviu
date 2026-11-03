import AppKit
import SwiftUI

/// Opens and closes the review window from places that aren't inside it, like the menu bar or a notification.
/// In menu bar mode Riviu leaves the Dock while the window is closed, and comes back when it reopens.
final class MainWindow {
    static let id = "review"

    private var openWindow: OpenWindowAction?

    func remember(_ action: OpenWindowAction) {
        openWindow = action
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        openWindow?(id: Self.id)
        NSApp.activate()
    }

    func didClose(keepsRunningInMenuBar: Bool) {
        if keepsRunningInMenuBar {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// Decides whether closing the window quits Riviu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set when the window first appears.
    var settings: AppSettings?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(settings?.keepsRunningInMenuBar ?? false)
    }
}

extension View {
    /// Hands this view's `openWindow` action to `MainWindow`, which has no environment of its own.
    func remembersOpenWindow(in mainWindow: MainWindow) -> some View {
        modifier(RemembersOpenWindow(mainWindow: mainWindow))
    }
}

private struct RemembersOpenWindow: ViewModifier {
    let mainWindow: MainWindow
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { mainWindow.remember(openWindow) }
    }
}

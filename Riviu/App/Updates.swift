import Sparkle
import SwiftUI

/// Checks for new versions of Riviu with Sparkle. Releases and their announcement (appcast.xml) are on the
/// GitHub releases page, set in Config/Info.plist. Debug builds never check.
final class Updates {
    private let controller: SPUStandardUpdaterController

    init() {
        #if DEBUG
        let checksForUpdates = false
        #else
        let checksForUpdates = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: checksForUpdates, updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    var canCheck: Bool {
        #if DEBUG
        false
        #else
        controller.updater.canCheckForUpdates
        #endif
    }

    func checkNow() {
        controller.checkForUpdates(nil)
    }
}

/// Riviu > Check for Updates…
struct UpdateCommands: Commands {
    let updates: Updates

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updates.checkNow() }
                .disabled(!updates.canCheck)
        }
    }
}

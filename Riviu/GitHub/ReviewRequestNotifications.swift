import AppKit
import UserNotifications

/// Posts "review requested" notifications, and opens the pull request when one is clicked.
final class ReviewRequestNotifications: NSObject, UNUserNotificationCenterDelegate {
    /// Called with the pull request whose notification was clicked.
    var onOpen: ((PullRequestReference) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Posting again for the same pull request replaces its notification, so the AI result can update it.
    func post(title: String, body: String, about reference: PullRequestReference, playsSound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = reference.id
        content.body = body
        content.sound = playsSound ? .default : nil
        content.userInfo = ["repository": reference.repository, "number": reference.number]
        let request = UNNotificationRequest(identifier: "review-request:\(reference.id)", content: content, trigger: nil)
        center.add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even while Riviu is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let repository = info["repository"] as? String, let number = info["number"] as? Int else { return }
        let reference = PullRequestReference(repository: repository, number: number)
        await MainActor.run {
            NSApp.activate()
            onOpen?(reference)
        }
    }
}

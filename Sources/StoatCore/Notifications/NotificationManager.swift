import Foundation
import UserNotifications

/// Stoat's push service only signs pushes for the official app (`chat.revolt.app`), so Yuki
/// posts local notifications while it's connected instead.
@MainActor
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()

    public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    public var onOpenChannel: ((String) -> Void)?

    /// UserNotifications traps when there's no host app, as in unit tests, so it's skipped there.
    private static let hasHostApp = NSClassFromString("XCTestCase") == nil && Bundle.main.bundleIdentifier != nil

    private var center: UNUserNotificationCenter? {
        Self.hasHostApp ? .current() : nil
    }

    private override init() {
        super.init()
        center?.delegate = self
    }

    public func refreshAuthorizationStatus() async {
        guard let center else { return }
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    /// Asks for permission. Only call this from an explicit user action.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            guard let center else { return false }
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            DiagnosticsLog.log(.app, "Notification permission request failed: \(error)")
            return false
        }
    }

    public var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    public func updateBadgeCount(_ count: Int) {
        guard isAuthorized else { return }
        center?.setBadgeCount(count) { error in
            if let error {
                DiagnosticsLog.log(.app, "Couldn't set the badge: \(error)")
            }
        }
    }

    public func postMessageNotification(title: String, body: String, channelId: String, messageId: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = channelId
        content.userInfo = ["channel": channelId]
        let request = UNNotificationRequest(identifier: messageId, content: content, trigger: nil)
        center?.add(request)
    }

    public func removeNotifications(forChannel channelId: String) {
        Task {
            guard let center else { return }
            let ids = await center.deliveredNotifications()
                .filter { $0.request.content.threadIdentifier == channelId }
                .map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // In-app banners are shown by the UI while Yuki is in the foreground.
        []
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let channelId = response.notification.request.content.userInfo["channel"] as? String else { return }
        await MainActor.run {
            NotificationManager.shared.onOpenChannel?(channelId)
        }
    }
}

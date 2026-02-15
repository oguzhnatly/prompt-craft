import Foundation
import UserNotifications

final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    func requestPermissionIfNeeded() {
        let key = AppConstants.UserDefaultsKeys.notificationPermissionRequested
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Logger.shared.warning("Notification permission error", error: error)
            }
            Logger.shared.info("Notification permission \(granted ? "granted" : "denied")")
        }
    }

    // MARK: - Send Notifications

    func notifyOptimizationComplete(style: String, characterCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Optimization Complete"
        content.body = "Optimized with \(style) (\(characterCount) chars). Result is on your clipboard."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func notifyOptimizationFailed(error: String) {
        let content = UNMutableNotificationContent()
        content.title = "Optimization Failed"
        content.body = error
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner even when app is in foreground
        completionHandler([.banner, .sound])
    }
}

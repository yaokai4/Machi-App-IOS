import Foundation

enum NotificationPreferenceService {
    static func isEnabled(_ type: NotificationType, recipientUserId: String) -> Bool {
        UserDefaults.standard.object(forKey: key(type, recipientUserId: recipientUserId)) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool, type: NotificationType, recipientUserId: String) {
        UserDefaults.standard.set(enabled, forKey: key(type, recipientUserId: recipientUserId))
    }

    private static func key(_ type: NotificationType, recipientUserId: String) -> String {
        "notification.\(recipientUserId).\(type.rawValue)"
    }
}

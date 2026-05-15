import UserNotifications

enum NotificationService {

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sendCopyComplete(copied: Int, skipped: Int, errors: Int) {
        let content = UNMutableNotificationContent()
        content.title = "コピー完了"
        var parts = ["\(copied)件コピー"]
        if skipped > 0 { parts.append("\(skipped)件スキップ") }
        if errors  > 0 { parts.append("\(errors)件エラー") }
        content.body = parts.joined(separator: " / ")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

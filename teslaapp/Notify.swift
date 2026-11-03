import Foundation
import UserNotifications

/// 本地通知（充电完成等），不依赖推送证书
enum Notify {
    private static var asked = false

    static func requestPermission() {
        guard !asked else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String, id: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    /// 充电完成提醒：从上一次「正在充电」变成「已充满/停止」时触发
    static func chargingFinishedIfNeeded(prev: String?, now: String?, battery: Int?, limit: Int?) {
        let wasCharging = (prev ?? "").lowercased().contains("charging")
        let stillCharging = (now ?? "").lowercased().contains("charging")
        guard wasCharging, !stillCharging else { return }
        let lmt = limit ?? 100
        let bat = battery ?? 0
        // 只有接近充满才算「完成」，否则视为中途拔枪
        guard bat >= lmt - 2 || bat >= 99 else { return }
        send(title: "充电完成",
             body: "已充到 \(bat)%\(batterySuffix(bat: bat, limit: lmt))",
             id: "charge-done-\(Int(Date().timeIntervalSince1970))")
    }

    private static func batterySuffix(bat: Int, limit: Int) -> String {
        bat >= limit - 1 ? "（已到充电上限 \(limit)%）" : ""
    }
}

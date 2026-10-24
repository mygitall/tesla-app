import UIKit

/// 触感反馈（iPhone 的 Taptic Engine）
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()
    private static let select = UISelectionFeedbackGenerator()

    /// 按钮点击：轻触
    static func tap() {
        light.prepare()
        light.impactOccurred()
    }

    /// 切换类操作：柔和
    static func toggle() {
        soft.prepare()
        soft.impactOccurred()
    }

    /// 选择/切页
    static func selection() {
        select.prepare()
        select.selectionChanged()
    }

    /// 命令成功
    static func success() {
        notify.prepare()
        notify.notificationOccurred(.success)
    }

    /// 命令失败
    static func error() {
        notify.prepare()
        notify.notificationOccurred(.error)
    }

    /// 长按/警告
    static func warning() {
        notify.prepare()
        notify.notificationOccurred(.warning)
    }
}

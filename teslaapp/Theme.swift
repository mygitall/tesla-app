import SwiftUI

enum Theme {
    static let bg    = Color(red: 0.043, green: 0.051, blue: 0.063)   // #0B0D10
    static let card  = Color(red: 0.078, green: 0.090, blue: 0.110)   // #14171C
    static let line  = Color.white.opacity(0.08)
    static let green = Color(red: 0.239, green: 0.863, blue: 0.518)   // #3DDC84
    static let amber = Color(red: 0.961, green: 0.647, blue: 0.141)
    static let red   = Color(red: 0.937, green: 0.325, blue: 0.314)
    static let blue  = Color(red: 0.357, green: 0.612, blue: 0.965)
    static let text  = Color.white
    static let dim   = Color.white.opacity(0.42)
}

/// 统一卡片容器
struct Card<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

/// 小圆角标签
struct Chip: View {
    let text: String
    var color: Color = Theme.dim
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.app(11, .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(filled ? color.opacity(0.14) : Color.clear)
            )
            .overlay(
                Capsule().stroke(color.opacity(0.45), lineWidth: 1)
            )
    }
}


// MARK: - 动态字体（跟随系统「文字大小」设置）

import UIKit
import Combine

/// 全局字号缩放因子：由系统「设置 → 显示与亮度 → 文字大小」决定。
/// 设计字号保持不变，仅按用户偏好等比放大（上限 1.35，避免撑破卡片）。
enum TypoScale {
    /// 0...0.35 的额外放大比例
    private(set) static var extra: CGFloat = 0

    static func factor(_ size: CGFloat) -> CGFloat {
        1 + extra * min(1, 12 / max(size, 8))   // 小字放大比例略高，大字略低
    }

    static func apply(_ category: UIContentSizeCategory) {
        switch category {
        case .extraSmall: extra = -0.06
        case .small: extra = -0.03
        case .medium: extra = 0
        case .large: extra = 0
        case .extraLarge: extra = 0.08
        case .extraExtraLarge: extra = 0.16
        case .extraExtraExtraLarge: extra = 0.24
        case .accessibilityMedium: extra = 0.30
        default: extra = 0.35
        }
    }

    static func start() {
        apply(UIApplication.shared.preferredContentSizeCategory)
        NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory.didChangeNotification,
            object: nil, queue: .main
        ) { note in
            if let c = note.userInfo?[UIContentSizeCategory.newValueUserInfoKey] as? UIContentSizeCategory {
                apply(c)
            } else {
                apply(UIApplication.shared.preferredContentSizeCategory)
            }
            TypoScale.bump.send()
        }
    }

    /// 变化信号（让根视图重建，字号才会刷新）
    static let bump = PassthroughSubject<Void, Never>()
}

extension Font {
    /// 支持动态字体的系统字体
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * TypoScale.factor(size), weight: weight)
    }
    static func appMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * TypoScale.factor(size), weight: weight, design: .monospaced)
    }
}

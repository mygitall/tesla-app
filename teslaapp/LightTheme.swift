import SwiftUI

/// 深色高端主题（实测自参考设计稿）
enum L {
    static let bg      = Color(hex: 0x08090A)   // 页面背景
    static let card    = Color(hex: 0x141517)   // 卡片
    static let card2   = Color(hex: 0x1A1B1D)   // 卡片内次级块
    static let text    = Color(hex: 0xF5F5F5)   // 主文字
    static let sub     = Color(hex: 0x7A7A7A)   // 次文字
    static let dim     = Color(hex: 0x4A4A4A)   // 极弱文字
    static let line    = Color(hex: 0x1E1F20)   // 分割线
    static let sand    = Color(hex: 0xC8A880)   // 暖沙金（强调色）
    static let glow    = Color(hex: 0x312B22)   // 顶部暖光晕

    // 状态色（克制使用）
    static let green   = Color(hex: 0x6FA37C)
    static let orange  = Color(hex: 0xC8A880)   // 统一到沙金
    static let blue    = Color(hex: 0x7C93AD)
    static let purple  = Color(hex: 0x9B84A8)

    static let fill    = Color(hex: 0x1A1B1D)   // 兼容旧代码的块底色
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

/// 白色圆角卡片
struct LCard<Content: View>: View {
    var pad: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(L.card))
    }
}

/// 顶部数值胶囊
struct Pill: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 17, weight: .semibold)).foregroundColor(L.text)
            Text(label).font(.system(size: 10)).foregroundColor(L.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(L.fill))
    }
}

/// 小标签（哨兵 / 已锁车 等）
struct Tag: View {
    var icon: String? = nil
    let text: String
    var color: Color = L.sub
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Text(icon).font(.system(size: 11)) }
            Text(text).font(.system(size: 12)).foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(L.fill))
    }
}

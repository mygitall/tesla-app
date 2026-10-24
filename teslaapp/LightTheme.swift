import SwiftUI

/// 深色主题（#151717 背景 / #efefef 文字）
enum L {
    static let bg = Color(hex: 0x151717)       // 背景
    static let card = Color(hex: 0x1C1F20)     // 卡片
    static let text = Color(hex: 0xEFEFEF)     // 主文字
    static let sub = Color(hex: 0x8F9798)      // 次要文字
    static let line = Color.white.opacity(0.08)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.12)   // #FF9E1F
    static let green = Color(hex: 0x34C759)
    static let blue = Color(hex: 0x0A84FF)
    static let purple = Color(hex: 0xBF5AF2)
    static let fill = Color(hex: 0x232829)     // 胶囊/方块底
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

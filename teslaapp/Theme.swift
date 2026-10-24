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
            .font(.system(size: 11, weight: .semibold))
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

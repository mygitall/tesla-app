import SwiftUI

/// 今日卡片里的灰色圆角小方块
/// 用法：TodayStatTile("77.3 km", "今日里程")
struct TodayStatTile: View {
    let value: String
    let label: String
    var tint: Color? = nil
    var showChevron: Bool = false

    init(_ value: String, _ label: String, tint: Color? = nil, showChevron: Bool = false) {
        self.value = value
        self.label = label
        self.tint = tint
        self.showChevron = showChevron
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint ?? L.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(L.sub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(L.sub.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(L.fill)
        )
    }
}

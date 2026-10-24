import SwiftUI

/// 首页「今日行程」卡片
struct TodayTripCard: View {
    let distanceKm: Double
    let durationText: String      // 形如 "1:15"
    let energyKwh: Double

    var background: Color = L.card

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            // 标题行
            HStack {
                Text("今日行程")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(L.sub)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(L.dim)
            }

            // 三栏数据
            HStack(spacing: 0) {
                cell(String(format: "%.1f", distanceKm), "km", leading: 0)
                divider
                cell(durationText, "小时", leading: 14)
                divider
                cell(String(format: "%.0f", energyKwh), "kWh", leading: 14)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(background)
        )
    }

    /// 数值 + 单位同行，基线对齐
    private func cell(_ value: String, _ unit: String, leading: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .medium))
                .monospacedDigit()
                .foregroundColor(L.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(unit)
                .font(.system(size: 10.5))
                .foregroundColor(L.sub)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(L.line)
            .frame(width: 1, height: 24)
    }
}

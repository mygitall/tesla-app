import SwiftUI

/// 首页「今日行程」卡片
/// 默认红色背景（可改 background 参数换回卡片色 L.card）
struct TodayTripCard: View {
    let distanceKm: Double
    let durationText: String      // 形如 "1:15"
    let energyKwh: Double

    var background: Color = L.red
    var titleColor: Color = .white.opacity(0.92)
    var valueColor: Color = .white
    var unitColor: Color = .white.opacity(0.72)
    var dividerColor: Color = .white.opacity(0.22)

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("今日行程")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(titleColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(titleColor.opacity(0.6))
            }
            HStack(spacing: 0) {
                metric(String(format: "%.1f", distanceKm), "km")
                divider
                metric(durationText, "小时")
                divider
                metric(String(format: "%.0f", energyKwh), "kWh")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(background)
        )
    }

    private func metric(_ v: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v)
                .font(.system(size: 23, weight: .regular))
                .monospacedDigit()
                .foregroundColor(valueColor)
            Text(unit)
                .font(.system(size: 11))
                .foregroundColor(unitColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(dividerColor).frame(width: 1, height: 34)
    }
}

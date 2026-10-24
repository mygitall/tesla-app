import SwiftUI

/// 电量圆环
struct BatteryRing: View {
    let percent: Int?
    let rangeKm: Int?
    var charging: Bool = false

    private var color: Color { charging ? Theme.green : Theme.green }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 15)

            Circle()
                .trim(from: 0, to: max(0, min(1, CGFloat(percent ?? 0) / 100)))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 14)
                .animation(.easeInOut(duration: 0.7), value: percent)

            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(percent.map(String.init) ?? "—")
                        .font(.system(size: 58, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 19, weight: .light))
                        .foregroundColor(Theme.dim)
                        .baselineOffset(8)
                }
                Text(rangeKm.map { "\($0) km" } ?? "无数据")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.dim)
            }
        }
        .frame(width: 210, height: 210)
        .padding(.vertical, 6)
    }
}

/// 数据小方块
struct StatTile: View {
    let title: String
    let value: String
    var accent: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(Theme.dim)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }
}

/// 大号操作按钮
struct ActionButton: View {
    let icon: String
    let title: String
    var tint: Color = Theme.green
    var armed: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .regular))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .foregroundColor(armed ? Theme.amber : tint)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill((armed ? Theme.amber : tint).opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke((armed ? Theme.amber : tint).opacity(0.40), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

import SwiftUI

/// 电量 / 充电卡片
/// —— 首页那块灰色卡片，独立成型，可点击进入充电详情页
struct PowerCard: View {
    let s: VehicleSummary?
    let isCharging: Bool

    private var battery: Int { s?.battery ?? 0 }
    private var progress: CGFloat { CGFloat(min(max(Double(battery) / 100, 0), 1)) }

    var body: some View {
        LCard {
            VStack(spacing: 14) {
                HStack(spacing: 18) {
                    ring
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            miniStat(chargingMinutes, "已充时长")
                            miniStat(minutesToFull, "预计剩余")
                        }
                        HStack {
                            miniStat(energyAdded, "已充入")
                            miniStat(rangeAdded, "已增加")
                        }
                    }
                }

                HStack(spacing: 8) {
                    squareStat(amps, "电流")
                    squareStat(volts, "电压")
                    squareStat(kw, "功率")
                    squareStat(rate, "速度")
                }

                // 可点击提示
                HStack(spacing: 4) {
                    Text("查看充电详情")
                        .font(.system(size: 10))
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                }
                .foregroundColor(L.sub)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: 环形

    private var ring: some View {
        ZStack {
            Circle().stroke(L.fill, lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(isCharging ? L.orange : L.green,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(battery)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(L.text)
                Text("%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(L.sub)
                Text(isCharging ? "充电中" : "电量")
                    .font(.system(size: 10))
                    .foregroundColor(isCharging ? L.orange : L.green)
            }
        }
        .frame(width: 96, height: 96)
    }

    // MARK: 数值

    private var chargingMinutes: String {
        // 已充时长用「已充入 ÷ 当前功率」粗估；没在充电则 —
        guard isCharging,
              let e = s?.energyAddedKwh, e > 0,
              let p = s?.chargerPower, p > 0.1 else { return "—" }
        let minutes = Int((e / p) * 60)
        return minutes >= 60 ? "\(minutes / 60) 时 \(minutes % 60) 分" : "\(minutes) 分"
    }

    private var minutesToFull: String {
        guard let m = s?.minutesToFull, m > 0 else { return "—" }
        return m >= 60 ? "\(m / 60) 时 \(m % 60) 分" : "\(m) 分"
    }

    private var energyAdded: String {
        guard let e = s?.energyAddedKwh, e > 0 else { return "—" }
        return String(format: "+%.1f 度", e)
    }

    private var rangeAdded: String {
        guard let r = s?.chargeRate, r > 0 else { return "—" }
        return "+\(r) 公里"
    }

    private var amps: String {
        guard let a = s?.chargerCurrent, a > 0 else { return "—" }
        return "\(Int(a)) A"
    }

    private var volts: String {
        guard let v = s?.chargerVoltage, v > 50 else { return "—" }
        return "\(Int(v)) V"
    }

    private var kw: String {
        guard let p = s?.chargerPower, p > 0 else { return "—" }
        return String(format: "%.1f kW", p)
    }

    private var rate: String {
        guard let r = s?.chargeRate, r > 0 else { return "—" }
        return "\(r) km/h"
    }

    // MARK: 小部件

    private func miniStat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 17, weight: .semibold)).foregroundColor(L.text)
            Text(l).font(.system(size: 10)).foregroundColor(L.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func squareStat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 14, weight: .semibold)).foregroundColor(L.text)
            Text(l).font(.system(size: 10)).foregroundColor(L.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(L.fill))
    }
}

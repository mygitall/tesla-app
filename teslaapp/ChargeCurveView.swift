import SwiftUI
import UIKit

/// 充电曲线组件
/// 支持：切换某次充电、横轴电量/时间、功率+电压+电流多线、导出 CSV
struct ChargeCurveView: View {
    let points: [ChargeCurvePoint]
    let sessions: [ChargeSessionItem]
    let selectedStart: Int?
    var onSelectSession: (Int?) -> Void
    var onExport: () -> Void

    @State private var xMode: XMode = .soc
    @State private var series: Set<Series> = [.power]

    enum XMode: String, CaseIterable { case soc = "电量", time = "时间" }
    enum Series: String, CaseIterable, Hashable {
        case power = "功率", voltage = "电压", current = "电流"
        var color: Color { self == .power ? L.orange : (self == .voltage ? L.blue : L.green) }
        var unit: String { self == .power ? "kW" : (self == .voltage ? "V" : "A") }
    }

    private var valid: [ChargeCurvePoint] { points.filter { $0.power > 0 } }

    // MARK: 数据范围

    private var socRange: (Double, Double) {
        let s = valid.compactMap { $0.battery.map(Double.init) }
        guard let mn = s.min(), let mx = s.max() else { return (0, 100) }
        return (mn, max(mx, mn + 1))
    }

    private func maxOf(_ s: Series) -> Double {
        switch s {
        case .power:   return valid.map(\.power).max() ?? 1
        case .voltage: return valid.compactMap(\.voltage).max() ?? 1
        case .current: return valid.compactMap(\.current).max() ?? 1
        }
    }

    private func value(_ p: ChargeCurvePoint, _ s: Series) -> Double? {
        switch s {
        case .power:   return p.power
        case .voltage: return p.voltage
        case .current: return p.current
        }
    }

    // MARK: 视图

    var body: some View {
        LCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !sessions.isEmpty { sessionChips }
                if valid.count >= 2 {
                    toggles
                    chart.frame(height: 160)
                    axis
                    legend
                } else {
                    emptyHint
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundColor(L.orange)
            Text("充电曲线").font(.system(size: 13, weight: .semibold)).foregroundColor(L.text)
            Spacer()
            if !valid.isEmpty {
                Button(action: onExport) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 10))
                        Text("导出").font(.system(size: 10))
                    }
                    .foregroundColor(L.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 可切换的充电记录
    private var sessionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sessions) { s in
                    let active = selectedStart == s.startTs
                    Button {
                        onSelectSession(s.startTs)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dateText(s.startTs))
                                .font(.system(size: 10, weight: active ? .semibold : .regular))
                                .foregroundColor(active ? Color(hex: 0x151717) : L.text)
                            Text("\(s.startBattery ?? 0)%→\(s.endBattery ?? 0)% · \(String(format: "%.1f", s.energyKwh))度")
                                .font(.system(size: 8))
                                .foregroundColor(active ? Color(hex: 0x151717).opacity(0.7) : L.sub)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(active ? L.orange : L.fill))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// 横轴模式 + 曲线开关
    private var toggles: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(XMode.allCases, id: \.self) { m in
                    Button { xMode = m } label: {
                        Text(m.rawValue)
                            .font(.system(size: 10, weight: xMode == m ? .semibold : .regular))
                            .foregroundColor(xMode == m ? Color(hex: 0x151717) : L.text)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(xMode == m ? L.text.opacity(0.85) : L.fill))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(Series.allCases, id: \.self) { s in
                    Button {
                        if series.contains(s) { if series.count > 1 { series.remove(s) } }
                        else { series.insert(s) }
                    } label: {
                        HStack(spacing: 3) {
                            Circle().fill(s.color).frame(width: 5, height: 5)
                            Text(s.rawValue).font(.system(size: 10))
                                .foregroundColor(series.contains(s) ? L.text : L.sub)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(series.contains(s) ? L.fill : Color.clear))
                        .overlay(Capsule().stroke(series.contains(s) ? Color.clear : L.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    // MARK: 图表

    private var chart: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ForEach(0..<4) { i in
                    let y = h * CGFloat(i) / 3
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }.stroke(L.line, lineWidth: 0.6)
                }
                ForEach(Series.allCases, id: \.self) { s in
                    if series.contains(s) {
                        path(for: s, w: w, h: h)
                            .stroke(s.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
    }

    /// x 归一化
    private func xPos(_ p: ChargeCurvePoint, _ w: CGFloat) -> CGFloat? {
        if xMode == .soc {
            guard let b = p.battery else { return nil }
            let (mn, mx) = socRange
            return CGFloat((Double(b) - mn) / (mx - mn)) * w
        } else {
            guard let first = valid.first, let last = valid.last, last.ts > first.ts else { return 0 }
            return CGFloat(Double(p.ts - first.ts) / Double(last.ts - first.ts)) * w
        }
    }

    private func path(for s: Series, w: CGFloat, h: CGFloat) -> Path {
        Path { p in
            let top = maxOf(s)
            var started = false
            for pt in valid {
                guard let x = xPos(pt, w), let v = value(pt, s) else { continue }
                let y = h - CGFloat(min(v / (top * 1.05), 1.0)) * h
                if !started { p.move(to: CGPoint(x: x, y: y)); started = true }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }

    private var axis: some View {
        HStack {
            Text(leftLabel).font(.system(size: 9)).foregroundColor(L.sub)
            Spacer()
            Text(xMode == .soc ? "电量 →" : "时间 →")
                .font(.system(size: 9)).foregroundColor(L.sub.opacity(0.7))
            Spacer()
            Text(rightLabel).font(.system(size: 9)).foregroundColor(L.sub)
        }
    }

    private var leftLabel: String {
        if xMode == .soc { return "\(Int(socRange.0))%" }
        guard let f = valid.first else { return "" }
        return timeText(f.ts)
    }
    private var rightLabel: String {
        if xMode == .soc { return "\(Int(socRange.1))%" }
        guard let l = valid.last else { return "" }
        return timeText(l.ts)
    }

    /// 图例：显示每条线各自的峰值
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(Series.allCases, id: \.self) { s in
                if series.contains(s) {
                    HStack(spacing: 3) {
                        Circle().fill(s.color).frame(width: 5, height: 5)
                        Text("\(s.rawValue) \(String(format: "%.1f", maxOf(s)))\(s.unit)")
                            .font(.system(size: 9)).foregroundColor(L.sub)
                    }
                }
            }
            Spacer()
            Text("\(valid.count) 点").font(.system(size: 9)).foregroundColor(L.sub.opacity(0.7))
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 22)).foregroundColor(L.sub)
            Text("这次充电的数据点太少，画不出曲线")
                .font(.system(size: 11)).foregroundColor(L.text)
            Text("下次充电时每 20 秒采一个点，曲线会完整")
                .font(.system(size: 9)).foregroundColor(L.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: 格式化

    private func dateText(_ ts: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
    private func timeText(_ ts: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}

/// iOS 分享面板（导出 CSV 用）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

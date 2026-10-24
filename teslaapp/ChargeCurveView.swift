import SwiftUI

/// 充电曲线：横轴电量（%），纵轴功率（kW）
/// 独立组件，嵌在充电详情页里
struct ChargeCurveView: View {
    let points: [ChargeCurvePoint]
    let peak: Double

    private var valid: [ChargeCurvePoint] {
        points.filter { $0.battery != nil }
    }

    private var socRange: (min: Double, max: Double) {
        let socs = valid.compactMap { $0.battery.map(Double.init) }
        guard let mn = socs.min(), let mx = socs.max() else { return (0, 100) }
        return (mn, max(mx, mn + 1))
    }

    private var peakY: Double {
        let p = valid.map(\.power).max() ?? peak
        return max(p * 1.18, 1)
    }

    var body: some View {
        LCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundColor(L.orange)
                    Text("充电曲线").font(.system(size: 13, weight: .semibold)).foregroundColor(L.text)
                    Spacer()
                    if !valid.isEmpty {
                        Text("峰值 \(String(format: "%.1f", valid.map(\.power).max() ?? 0)) kW")
                            .font(.system(size: 10)).foregroundColor(L.sub)
                    }
                }

                if valid.count >= 2 {
                    chart
                        .frame(height: 150)
                    axis
                } else {
                    emptyHint
                }
            }
        }
    }

    // MARK: 图表

    private var chart: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let (socMin, socMax) = socRange
            let spanX = socMax - socMin
            let maxY = peakY

            ZStack {
                // 横向网格线
                ForEach(0..<4) { i in
                    let y = h * CGFloat(i) / 3
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(L.line, lineWidth: 0.6)
                }

                // 面积
                areaPath(w: w, h: h, socMin: socMin, spanX: spanX, maxY: maxY)
                    .fill(
                        LinearGradient(
                            colors: [L.orange.opacity(0.35), L.orange.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                // 折线
                linePath(w: w, h: h, socMin: socMin, spanX: spanX, maxY: maxY)
                    .stroke(L.orange, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                // 末点圆点
                if let last = valid.last, let soc = last.battery {
                    let x = CGFloat((Double(soc) - socMin) / spanX) * w
                    let y = h - CGFloat(min(last.power / maxY, 1.0)) * h
                    Circle().fill(L.orange)
                        .frame(width: 6, height: 6)
                        .position(x: min(max(x, 3), w - 3), y: min(max(y, 3), h - 3))
                }
            }
        }
    }

    private func linePath(w: CGFloat, h: CGFloat, socMin: Double, spanX: Double, maxY: Double) -> Path {
        Path { p in
            var first = true
            for pt in valid {
                guard let soc = pt.battery else { continue }
                let x = CGFloat((Double(soc) - socMin) / spanX) * w
                let y = h - CGFloat(min(pt.power / maxY, 1.0)) * h
                if first { p.move(to: CGPoint(x: x, y: y)); first = false }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }

    private func areaPath(w: CGFloat, h: CGFloat, socMin: Double, spanX: Double, maxY: Double) -> Path {
        Path { p in
            var first = true
            var lastX: CGFloat = 0
            for pt in valid {
                guard let soc = pt.battery else { continue }
                let x = CGFloat((Double(soc) - socMin) / spanX) * w
                let y = h - CGFloat(min(pt.power / maxY, 1.0)) * h
                if first { p.move(to: CGPoint(x: x, y: h)); p.addLine(to: CGPoint(x: x, y: y)); first = false }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
                lastX = x
            }
            p.addLine(to: CGPoint(x: lastX, y: h))
            p.closeSubpath()
        }
    }

    // MARK: 坐标标注

    private var axis: some View {
        HStack {
            Text("\(Int(socRange.min))%")
                .font(.system(size: 9)).foregroundColor(L.sub)
            Spacer()
            Text("电量 →")
                .font(.system(size: 9)).foregroundColor(L.sub.opacity(0.7))
            Spacer()
            Text("\(Int(socRange.max))%")
                .font(.system(size: 9)).foregroundColor(L.sub)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 22)).foregroundColor(L.sub)
            Text("充电数据点太少，画不出曲线")
                .font(.system(size: 11)).foregroundColor(L.text)
            Text("下次插枪充电（每 20 秒采一个点）就能看到完整曲线")
                .font(.system(size: 9)).foregroundColor(L.sub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

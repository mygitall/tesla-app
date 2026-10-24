import SwiftUI

/// 充电详情页 —— 由首页 PowerCard 点击进入
/// 支持按「年 / 月」筛选充电统计
struct ChargeDetailView: View {
    @ObservedObject var api: TeslaAPI

    /// 选中的月份 key（"2026-10"）；nil = 整年
    @State private var selectedKey: String?
    @State private var allTime = true
    @State private var showBaselineEditor = false
    @State private var baseSessions = ""
    @State private var baseKwh = ""
    @State private var baseHours = ""
    @State private var baseKw = "60"
    @State private var year: Int = Calendar.current.component(.year, from: Date())

    private var s: VehicleSummary? { api.summary }
    private var isCharging: Bool { (s?.charging ?? "").lowercased() == "charging" }
    private var battery: Int { s?.battery ?? 0 }
    private var summary: ChargeSummaryResp? { api.chargeSummary }

    var body: some View {
        ZStack {
            L.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    periodPicker
                    heroCard
                    paramGrid
                    totalsCard
                    sessionListCard
                    sourceNote
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .navigationTitle("充电详情")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await api.refresh()
            await reload()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await api.refresh()
                        await reload()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 14))
                }
                .foregroundColor(L.text)
            }
        }
        .sheet(isPresented: $showBaselineEditor) {
            baselineEditor
        }
        .task {
            await api.loadChargeMonths()
            if allTime {
                await api.loadChargeSummaryAll()
            } else {
                await reload()
            }
        }
    }

    // MARK: 历史基线编辑

    private var baselineEditor: some View {
        NavigationView {
            Form {
                Section {
                    TextField("总充电次数", text: $baseSessions)
                        .keyboardType(.numberPad)
                    TextField("总充电量（度）", text: $baseKwh)
                        .keyboardType(.decimalPad)
                    TextField("总充电时长（小时，可留空）", text: $baseHours)
                        .keyboardType(.decimalPad)
                    TextField("假设充电功率（kW）", text: $baseKw)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("从特斯拉官方 App 抄过来的累计数字")
                } footer: {
                    Text("「总充电次数」「总充电量」从官方 App 抄。时长官方不显示，留空则按下面的假设功率估算（默认 60kW 快充桩）。填了真实小时数就以你填的为准。")
                }
            }
            .navigationTitle("历史充电数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showBaselineEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            let hours = Double(baseHours.replacingOccurrences(of: ",", with: ".")) ?? 0
                            await api.saveChargeBaseline(
                                sessions: Int(baseSessions) ?? 0,
                                kwh: Double(baseKwh) ?? 0,
                                durationMin: Int(hours * 60),
                                assumedKw: Double(baseKw) ?? 60
                            )
                            showBaselineEditor = false
                            await api.loadChargeSummaryAll()
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 时间筛选

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 12)).foregroundColor(L.orange)
                Text("充电统计").font(.system(size: 13, weight: .semibold)).foregroundColor(L.text)
                Spacer()
                if api.chargeLoading {
                    ProgressView().scaleEffect(0.6)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(title: "全部", active: allTime) {
                        allTime = true
                        selectedKey = nil
                        Task { await api.loadChargeSummaryAll() }
                    }
                    ForEach(api.chargeMonths) { m in
                        chip(title: "\(m.year)年\(m.month)月", active: !allTime && selectedKey == m.key) {
                            allTime = false
                            selectedKey = m.key
                            year = m.year
                            Task { await reload() }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if api.chargeMonths.isEmpty {
                Text("还没有充电记录（插枪充电后自动统计）")
                    .font(.system(size: 11)).foregroundColor(L.sub)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(L.card))
    }

    private func chip(title: String, active: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundColor(active ? Color(hex: 0x151717) : L.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? L.orange : L.fill)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 顶部大环形

    private var heroCard: some View {
        LCard {
            VStack(spacing: 16) {
                ZStack {
                    Circle().stroke(L.fill, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(Double(battery) / 100, 0), 1)))
                        .stroke(isCharging ? L.orange : L.green,
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(battery)")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(L.text)
                        Text("%")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(L.sub)
                    }
                }
                .frame(width: 160, height: 160)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isCharging ? L.orange : L.sub)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isCharging ? L.orange : L.sub)
                }

                if let limit = s?.chargeLimit {
                    Text("充电上限 \(limit)%")
                        .font(.system(size: 11))
                        .foregroundColor(L.sub)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var statusText: String {
        switch (s?.charging ?? "").lowercased() {
        case "charging": return "正在充电"
        case "starting": return "启动中"
        case "stopped": return "已停止充电"
        case "complete": return "充电完成"
        case "disconnected": return "未连接充电枪"
        default: return s?.charging.map { "状态：\($0)" } ?? "未知"
        }
    }

    // MARK: 四个大参数

    private var paramGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                bigStat("电流", amps, "charger_actual_current")
                bigStat("电压", volts, "charger_voltage")
            }
            HStack(spacing: 10) {
                bigStat("功率", kw, "charger_power")
                bigStat("速度", rate, "charge_rate")
            }
        }
    }

    private func bigStat(_ title: String, _ value: String, _ field: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundColor(L.sub)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(value == "—" ? L.sub : L.text)
            Text(field)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(L.sub.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(L.card))
    }

    // MARK: 该期间总数据

    private var totalsCard: some View {
        LCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(periodTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(L.text)
                    Spacer()
                    Text("共 \(summary?.totals.count ?? 0) 次")
                        .font(.system(size: 11)).foregroundColor(L.sub)
                }

                HStack(spacing: 8) {
                    totalTile("总电量", String(format: "%.1f 度", summary?.totals.energyKwh ?? 0), L.orange)
                    totalTile((summary?.totals.minutesEstimated ?? false) ? "总时长（估算）" : "总时长",
                              ((summary?.totals.minutesEstimated ?? false) ? "≈ " : "")
                              + durText(summary?.totals.minutes ?? 0),
                              L.blue)
                }
                HStack(spacing: 8) {
                    totalTile("峰值功率", String(format: "%.1f kW", summary?.totals.peakPower ?? 0), L.green)
                    totalTile("平均每次", String(format: "%.1f 度", summary?.totals.avgKwh ?? 0), L.purple)
                }

                if allTime, summary?.totals.minutesEstimated == true,
                   let kw = summary?.totals.assumedKw, kw > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 9))
                        Text("历史时长按 \(String(format: "%.0f", kw)) kW 估算（可改），也可手工填真实时长")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(L.orange)
                }

                if allTime, let b = summary?.baseline, b.sessions > 0 || b.kwh > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle").font(.system(size: 9))
                        Text("含官方 App 历史基线 \(b.sessions) 次 / \(String(format: "%.0f", b.kwh)) 度")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(L.sub)
                }

                Button {
                    baseSessions = "\(summary?.baseline?.sessions ?? 0)"
                    baseKw = String(format: "%.0f", summary?.baseline?.assumedKw ?? 60)
                    baseKwh = String(format: "%.0f", summary?.baseline?.kwh ?? 0)
                    if let dm = summary?.baseline?.durationMin, dm > 0 {
                        baseHours = String(format: "%.1f", Double(dm) / 60.0)
                    } else {
                        baseHours = ""
                    }
                    showBaselineEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 10))
                        Text("导入官方 App 历史数据").font(.system(size: 11))
                    }
                    .foregroundColor(L.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var periodTitle: String {
        if allTime { return "全部时间" }
        if let key = selectedKey {
            let parts = key.split(separator: "-")
            if parts.count == 2 {
                return "\(parts[0]) 年 \(Int(parts[1]) ?? 0) 月"
            }
            return key
        }
        return "\(year) 年全年"
    }

    private func totalTile(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundColor(L.sub)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(L.fill))
    }

    // MARK: 明细

    private var sessionListCard: some View {
        LCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("充电明细").font(.system(size: 13, weight: .semibold)).foregroundColor(L.text)

                if let list = summary?.sessions, !list.isEmpty {
                    ForEach(list.prefix(20)) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dateText(item.startTs))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(L.text)
                                Text("\(item.startBattery ?? 0)% → \(item.endBattery ?? 0)%")
                                    .font(.system(size: 10)).foregroundColor(L.sub)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f 度", item.energyKwh))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(L.orange)
                                Text("\(item.durationMin) 分钟 · 峰值 \(String(format: "%.1f", item.peakPower))kW")
                                    .font(.system(size: 9)).foregroundColor(L.sub)
                            }
                        }
                        .padding(.vertical, 6)
                        if item.id != list.prefix(20).last?.id {
                            Divider().background(L.line)
                        }
                    }
                } else {
                    Text("该时间段暂无充电记录")
                        .font(.system(size: 11)).foregroundColor(L.sub)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private var sourceNote: some View {
        Text("实时数值来自特斯拉 Fleet API 的 charge_state；统计基于每分钟采样推导的充电会话。未充电时电流/功率/速度为 0 属正常。")
            .font(.system(size: 10))
            .foregroundColor(L.sub)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: 数据

    private func reload() async {
        if allTime {
            await api.loadChargeSummaryAll()
            return
        }
        if let key = selectedKey {
            let parts = key.split(separator: "-")
            let y = Int(parts.first ?? "") ?? year
            let m = parts.count > 1 ? Int(parts[1]) : nil
            await api.loadChargeSummary(year: y, month: m)
        } else {
            await api.loadChargeSummary(year: year, month: nil)
        }
    }

    private func dateText(_ ts: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    private func durText(_ minutes: Int) -> String {
        if minutes <= 0 { return "0 分" }
        if minutes < 60 { return "\(minutes) 分" }
        return "\(minutes / 60) 时 \(minutes % 60) 分"
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
        guard let p = s?.chargerPower, p > 0 else { return "0.0 kW" }
        return String(format: "%.1f kW", p)
    }
    private var rate: String {
        guard let r = s?.chargeRate, r > 0 else { return "—" }
        return "\(r) km/h"
    }
}

import SwiftUI
import UIKit

/// 首页 · 高端深色风（按参考稿实测还原）
struct HomeView: View {
    @ObservedObject var api: TeslaAPI
    @ObservedObject private var ble = TeslaKey.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showBleLog = false
    /// 乐观锁状态：点下去立刻切换视觉，等服务器确认后清空
    @StateObject private var layout = HomeLayout.shared
    @State private var pendingLock: Bool?
    /// 乐观空调状态
    @State private var pendingClimate: Bool?
    /// 无钥匙启动二次确认
    @State private var confirmDrive = false
    @State private var showMoreActions = false
    /// 离车上锁开关的乐观状态
    @State private var pendingAutoLock: Bool?
    /// 定位失败提示
    @State private var posAlert: String?
    /// 顶部操作提示（执行中 / 成功 / 失败）
    @State private var toast: ToastInfo?
    /// 前台自动刷新定时器
    @State private var autoTimer: Timer?
    @State private var lastWakePing: Date?

    private var s: VehicleSummary? { api.summary }

    /// 优先用本地乐观状态，避免等网络
    /// 首次加载未完成 → 显示骨架屏（避免一屏 0 / -- 像坏了）
    private var skeletonMode: Bool { s == nil && !api.initialLoadDone }

    private var isLocked: Bool { pendingLock ?? (s?.locked ?? true) }
    private var isClimateOn: Bool { pendingClimate ?? (s?.climateOn ?? false) }
    private var isCharging: Bool { (s?.charging ?? "").lowercased() == "charging" }

    // 实测色板
    private let cardRadius: CGFloat = 18
    private let hPad: CGFloat = 20

    var body: some View {
        NavigationView {
            ZStack {
                background
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        titleBlock
                        ForEach(layout.order, id: \.self) { id in
                            if !layout.hidden.contains(id) {
                                cardSlot(id)
                            }
                        }
                        if !layout.hidden.isEmpty {
                            Button {
                                Haptics.tap()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    for id in layout.hidden { layout.toggleHidden(id) }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "eye.slash").font(.app(10))
                                    Text("已隐藏 \(layout.hidden.count) 张卡片 · 恢复")
                                        .font(.app(11))
                                }
                                .foregroundColor(L.dim)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(L.card.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                        }

                        Color.clear.frame(height: 180)   // 底部留白：让最后一张卡能滚到标签栏之上
                    }
                    .padding(.horizontal, hPad)
                    .padding(.top, 80)
                    // 首屏骨架屏：首次加载还没完成时，用占位块代替一堆 0 和 --
                    .redacted(reason: skeletonMode ? .placeholder : [])
                    .allowsHitTesting(!skeletonMode)   // 数据没到前不允许点按钮发命令
                    .shimmering(skeletonMode)          // 微光扫过（替代原来的整页呼吸）
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .top) { toastBanner }
        }
        .navigationViewStyle(.stack)
        .refreshable { await api.refresh() }
        .task {
            ble.start()
            await api.loadLastLocation()
            await api.loadLastCharge()
            if api.summary == nil { await api.refresh() }
            startAutoRefresh()
        }
        .onAppear { if scenePhase == .active { startAutoRefresh() } }
        .onDisappear { stopAutoRefresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // 回到前台：复位在场判定 + 立刻刷一次 + 恢复定时刷新
                ble.appForegrounded()
                Task { if !api.busy { await api.refresh() } }
                startAutoRefresh()
            } else {
                ble.goBackground()
                stopAutoRefresh()
            }
        }
        .onChange(of: ble.connected) { on in
            // 蓝牙连上车辆 = 人就在车边，通知服务器开始高频采集
            if on {
                Task { await api.presence(present: ble.lastRSSI >= -80) }
                lastWakePing = Date()
            } else {
                // 蓝牙断开 = 人走了 → 立刻解除抑制，让自动锁生效
                Task { await api.presence(present: false) }
            }
        }
        .onChange(of: api.autoLockEnabled) { on in
            ble.autoLockEnabled = on          // 保持两边一致
        }
        .onChange(of: api.busy) { busy in
            if busy {
                showToast(api.actionText ?? "执行中…", loading: true, kind: .command)
            } else if let t = api.actionText, !t.isEmpty {
                showToast(t, error: api.actionIsError, kind: .command)
            }
        }
        .onChange(of: api.errorText) { err in
            if let e = err, !e.isEmpty, !api.busy { showToast(e, error: true, kind: .refresh) }
        }
        .sheet(isPresented: $showMoreActions) { moreActionsSheet }
        .confirmationDialog("无钥匙启动", isPresented: $confirmDrive, titleVisibility: .visible) {
            Button("确认启动（2 分钟内可驾驶）", role: .destructive) {
                Haptics.tap()
                Task { await api.command("drive", label: "无钥匙启动") }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("启动后 2 分钟内车辆可被直接开走，请确认你已在车旁。")
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(api: api) }
        .sheet(isPresented: $showBleLog) { BleLogSheet(ble: ble) }
        .alert(item: $posAlert) { msg in
            Alert(title: Text("无法定位"), message: Text(msg), dismissButton: .default(Text("好")))
        }
    }

    // MARK: 背景（顶部暖色光晕）

    private var background: some View {
        ZStack(alignment: .top) {
            L.bg.ignoresSafeArea()
            // 外层大光晕（面积大、很淡）
            RadialGradient(
                colors: [L.glow.opacity(0.20), L.bg.opacity(0)],
                center: .top, startRadius: 10, endRadius: 760
            )
            .frame(height: 900)
            // 内层核心（顶部稍浓，让最上方接近参考稿的暖度）
            RadialGradient(
                colors: [L.glow.opacity(0.70), L.bg.opacity(0)],
                center: .top, startRadius: 6, endRadius: 300
            )
            .frame(height: 380)
            .ignoresSafeArea()
        }
    }

    // MARK: 标题

    /// 一张卡：正常显示 / 折叠成一条 / 长按可折叠·移动·隐藏
    @ViewBuilder
    private func cardSlot(_ id: String) -> some View {
        if layout.collapsed.contains(id) {
            collapsedBar(id)
        } else {
            cardContent(id)
                .contextMenu {
                    Button {
                        Haptics.tap(); layout.toggleCollapse(id)
                    } label: { Label("折叠", systemImage: "rectangle.compress.vertical") }
                    Button {
                        Haptics.tap(); layout.move(id, by: -1)
                    } label: { Label("上移", systemImage: "arrow.up") }
                    Button {
                        Haptics.tap(); layout.move(id, by: 1)
                    } label: { Label("下移", systemImage: "arrow.down") }
                    Button(role: .destructive) {
                        Haptics.tap(); layout.toggleHidden(id)
                    } label: { Label("隐藏", systemImage: "eye.slash") }
                }
        }
    }

    @ViewBuilder
    private func cardContent(_ id: String) -> some View {
        switch HomeLayout.Card(rawValue: id) {
        case .car:      carSection
        case .battery:  batteryCard
        case .today:    todayCard
        case .actions:  actionRow
        case .charging: chargingCard
        case .phoneKey: phoneKeyCard
        case .location: locationCard
        case nil:       EmptyView()
        }
    }

    /// 折叠后的细条：点一下展开
    private func collapsedBar(_ id: String) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.18)) { layout.toggleCollapse(id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: layout.icon(id))
                    .font(.app(12))
                    .foregroundColor(L.sand.opacity(0.9))
                Text(layout.title(id))
                    .font(.app(12, .medium))
                    .foregroundColor(L.sub)
                Spacer()
                Text("展开").font(.app(10)).foregroundColor(L.dim)
                Image(systemName: "chevron.down")
                    .font(.app(9, .semibold))
                    .foregroundColor(L.dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(L.card.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { layout.move(id, by: -1) } label: { Label("上移", systemImage: "arrow.up") }
            Button { layout.move(id, by: 1) } label: { Label("下移", systemImage: "arrow.down") }
            Button { layout.toggleCollapse(id) } label: { Label("展开", systemImage: "rectangle.expand.vertical") }
            Button(role: .destructive) { layout.toggleHidden(id) } label: { Label("隐藏", systemImage: "eye.slash") }
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TESLA MODEL Y")
                    .font(.app(13, .medium))
                    .tracking(5)
                    .foregroundColor(L.text)
                Text("特斯拉 Model Y 标准续航版")
                    .font(.app(11))
                    .foregroundColor(L.sub)
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(statusText)
                        .font(.app(9.5))
                        .foregroundColor(statusColor.opacity(0.95))
                    if let t = api.lastRefreshAt {
                        Text("· 更新于 \(timeText(t))")
                            .font(.app(9.5))
                            .foregroundColor(L.dim)
                            .monospacedDigit()
                    }
                }
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.app(20, .light))
                    .foregroundColor(L.text.opacity(0.85))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
    }

    /// 车辆在线状态 + 数据新鲜度（解决"看到旧数据却以为是实时"）
    private var dataAgeMinutes: Int? {
        guard let t = api.lastRefreshAt else { return nil }
        return max(0, Int(Date().timeIntervalSince(t) / 60))
    }

    private var statusColor: Color {
        if api.summary == nil { return L.dim }
        let state = (api.summary?.state ?? "").lowercased()
        if state == "offline" { return L.red }
        guard let age = dataAgeMinutes else { return L.dim }
        if age >= 30 { return L.orange }      // 数据太旧
        if state == "asleep" { return L.sub }  // 车在休眠
        return L.ringGreen
    }

    private var statusText: String {
        if api.summary == nil { return "加载中" }
        let state = (api.summary?.state ?? "").lowercased()
        if state == "offline" { return "车辆离线" }
        guard let age = dataAgeMinutes else { return stateLabel(state) }
        if age >= 30 { return "\(stateLabel(state)) · 数据 \(age) 分钟前" }
        if age >= 2 { return "\(stateLabel(state)) · \(age) 分钟前" }
        return stateLabel(state)
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "online": return "在线"
        case "asleep": return "休眠"
        case "offline": return "离线"
        default: return "未知"
        }
    }

    // MARK: 车图

    private var carSection: some View {
        Group {
            if let ui = UIImage(named: "car") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 128)
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            } else {
                Image(systemName: "car.side.fill")
                    .font(.app(56, .ultraLight))
                    .foregroundColor(L.text.opacity(0.25))
                    .frame(height: 110)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: 电量卡（光环 + 续航 + 进度条，高度不变）

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // 电量光环
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: batteryRatio)
                        .stroke(L.ringGreen, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: batteryRatio)

                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(s?.battery ?? 0)")
                            .font(.system(size: batteryFontSize * TypoScale.factor(batteryFontSize), weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundColor(L.text)
                        Text("%")
                            .font(.app(9, .regular))
                            .foregroundColor(L.sub)
                    }
                    .fixedSize()
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text("续航 \(s?.rangeKm ?? 0) km")
                        .font(.app(12))
                        .foregroundColor(L.sub)
                    if let added = s?.addedKm, added > 0 {
                        Text("上次充电 +\(added) km")
                            .font(.app(10.5))
                            .foregroundColor(L.dim)
                    }
                }

                Spacer()
            }

            // 进度条（光环下方，铺满卡片宽度）
            progressBar

            // 车辆状态：把服务器已经在发、但一直没用的数据显示出来
            HStack(spacing: 0) {
                metricTile(icon: "thermometer.medium",
                           title: "车内",
                           value: s?.insideTemp.map { String(format: "%.1f°", $0) } ?? "--")
                dividerLine
                metricTile(icon: "sun.max",
                           title: "车外",
                           value: s?.outsideTemp.map { String(format: "%.0f°", $0) } ?? "--")
                dividerLine
                metricTile(icon: "gauge",
                           title: "总里程",
                           value: s?.odometerKm.map { formatKm($0) } ?? "--")
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(L.card))
    }

    /// "上次充电 49.5 kWh，增加 345 公里"
    private var lastChargeCaption: String? {
        guard let kwh = api.lastChargeKwh ?? s?.energyAddedKwh else { return nil }
        var text = String(format: "上次充电 %.1f kWh", kwh)
        if let km = api.lastChargeAddedKm ?? s?.addedKm {
            text += "，增加 \(km) 公里"
        }
        return text
    }

    private func statusPill(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.app(9))
            Text(text).font(.app(10))
        }
        .foregroundColor(active ? L.sand : L.dim)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(active ? L.sand.opacity(0.12) : L.card2))
    }

    private var locationCard: some View {
        // 优先实时坐标；没有就用最后一次记录的位置（并提示时间）
        let lat = s?.lat ?? api.lastLat
        let lon = s?.lon ?? api.lastLon
        let isStale = (s?.lat == nil)
        // 实时坐标来自 summary，是 WGS-84；last 坐标带 frame 标记
        let useGCJ = isStale && (api.lastLocFrame == "gcj")
        return LocationCard(lat: lat, lon: lon, isGCJ: useGCJ,
                            staleText: isStale ? staleLocationText : nil) { openCarInMaps() }
    }

    private var staleLocationText: String? {
        guard let ts = api.lastLocTs else { return "车辆休眠中，显示最后记录的位置" }
        let mins = max(0, Int(Date().timeIntervalSince1970 - Double(ts)) / 60)
        let rel = mins < 60 ? "\(mins) 分钟前" : (mins < 1440 ? "\(mins / 60) 小时前" : "\(mins / 1440) 天前")
        return "最后位置 · \(rel)（车休眠中）"
    }

    private func metricTile(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.app(9))
                    .foregroundColor(L.dim)
                Text(title)
                    .font(.app(9.5))
                    .foregroundColor(L.dim)
            }
            Text(value)
                .font(.app(12, .medium))
                .monospacedDigit()
                .foregroundColor(L.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var dividerLine: some View {
        Rectangle().fill(L.line).frame(width: 1, height: 22)
    }

    private func formatKm(_ km: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: km)) ?? "\(km)") + " km"
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill(L.ringGreen).frame(width: geo.size.width * batteryRatio)
            }
        }
        .frame(height: 3)
    }

    /// 三位数(100%)要用更小字号，否则 54pt 光环里放不下会被截断成 "1…%"
    private var batteryFontSize: CGFloat {
        let v = s?.battery ?? 0
        if v >= 100 { return 17 }
        if v >= 10 { return 21 }
        return 24
    }

    private var batteryRatio: Double {
        min(max(Double(s?.battery ?? 0) / 100, 0), 1)
    }

    // MARK: 今日卡

    private var todayCard: some View {
        NavigationLink(destination: TripsListView(api: api)) {
            TodayTripCard(
                distanceKm: s?.today?.distanceKm ?? 0,
                durationText: durText(s?.today?.driveMinutes, known: s?.today?.durationKnown),
                energyKwh: s?.today?.energyKwh ?? 0,
                energyEstimated: s?.today?.energyEstimated ?? false
            )
        }
        .buttonStyle(.plain)
    }

    private func metric(_ v: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v)
                .font(.app(23, .regular))
                .monospacedDigit()
                .foregroundColor(L.text)
            Text(unit)
                .font(.app(11))
                .foregroundColor(L.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var vDivider: some View {
        Rectangle().fill(L.line).frame(width: 1, height: 34)
    }

    // MARK: 快捷操作

    private var actionRow: some View {
        HStack(spacing: 10) {
            // 锁：显示当前状态，点击取反
            Button {
                guard !api.busy else { return }
                Haptics.toggle()
                let target = !isLocked
                withAnimation(.easeOut(duration: 0.12)) { pendingLock = target }
                Task {
                    await api.command(target ? "lock" : "unlock", label: target ? "上锁" : "解锁")
                    if api.actionIsError {
                        Haptics.error()
                        withAnimation(.easeOut(duration: 0.15)) { pendingLock = nil }
                        return
                    }
                    Haptics.success()
                    await api.refresh()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    withAnimation(.easeOut(duration: 0.15)) { pendingLock = nil }
                }
            } label: {
                actionLabel(title: isLocked ? "上锁" : "解锁",
                            icon: isLocked ? "lock" : "lock.open",
                            active: !isLocked, enabled: !api.busy)
            }
            .buttonStyle(.plain)
            .disabled(api.busy)

            // 启动：需要二次确认
            Button {
                guard !api.busy else { return }
                Haptics.tap()
                confirmDrive = true
            } label: {
                actionLabel(title: "启动", icon: "key", active: false, enabled: !api.busy)
            }
            .buttonStyle(.plain)
            .disabled(api.busy)

            // 空调：乐观更新
            Button {
                guard !api.busy else { return }
                Haptics.toggle()
                let target = !isClimateOn
                withAnimation(.easeOut(duration: 0.12)) { pendingClimate = target }
                Task {
                    await api.command(target ? "climate-on" : "climate-off",
                                      label: target ? "开空调" : "关空调")
                    if api.actionIsError {
                        Haptics.error()
                        withAnimation(.easeOut(duration: 0.15)) { pendingClimate = nil }
                        return
                    }
                    Haptics.success()
                    await api.refresh()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    withAnimation(.easeOut(duration: 0.15)) { pendingClimate = nil }
                }
            } label: {
                actionLabel(title: "空调", icon: "fanblades",
                            active: isClimateOn, enabled: !api.busy)
            }
            .buttonStyle(.plain)
            .disabled(api.busy)

            // 定位：本地操作，不受 busy 影响
            Button {
                Haptics.tap()
                openCarInMaps()
            } label: {
                actionLabel(title: "定位", icon: "location", active: false, enabled: true)
            }
            .buttonStyle(.plain)

            // 更多：后备箱/前备箱/哨兵/充电口/车窗/灯光
            Button {
                Haptics.tap()
                showMoreActions = true
            } label: {
                actionLabel(title: "更多", icon: "ellipsis", active: false, enabled: !api.busy)
            }
            .buttonStyle(.plain)
            .disabled(api.busy)
        }
    }

    /// 更多操作面板
    private var moreActionsSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    // 空调温度：只有在空调开启时才显示调节
                    if isClimateOn || pendingClimate == true {
                        VStack(spacing: 10) {
                            HStack {
                                Image(systemName: "thermometer.medium").font(.app(13)).foregroundColor(L.sand)
                                Text("空调温度").font(.app(13, .medium)).foregroundColor(L.text)
                                Spacer()
                                Text(tempText).font(.app(16, .semibold)).monospacedDigit().foregroundColor(L.text)
                            }
                            HStack(spacing: 10) {
                                tempButton("−2°", delta: -2)
                                tempButton("+2°", delta: +2)
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(L.card))
                    }

                    ForEach(moreGroups, id: \.0) { group, items in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group).font(.app(11)).foregroundColor(L.dim)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(items, id: \.id) { item in
                                    Button {
                                        Haptics.tap()
                                        dismissMore()
                                        Task { await api.command(item.action, label: item.title) }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: item.icon).font(.app(13)).foregroundColor(L.sand)
                                            Text(item.title).font(.app(13)).foregroundColor(L.text)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(L.card))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(api.busy)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(L.bg.ignoresSafeArea())
            .navigationTitle("更多操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismissMore() }
                }
            }
        }
    }

    private func dismissMore() {
        showMoreActions = false
    }

    private func tempButton(_ title: String, delta: Double) -> some View {
        Button {
            Haptics.tap()
            let base = s?.setTemp ?? 22
            let target = min(28, max(15, base + delta))
            Task { await api.setTemperature(target) }
        } label: {
            Text(title)
                .font(.app(14, .medium))
                .foregroundColor(L.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(L.card2))
        }
        .buttonStyle(.plain)
        .disabled(api.busy)
    }

    private var tempText: String {
        guard let t = s?.setTemp else { return "--°" }
        return String(format: "%.0f°", t)
    }

    private struct MoreItem: Identifiable {
        let id: String
        let title: String
        let icon: String
        let action: String
    }

    private var moreGroups: [(String, [MoreItem])] {
        [
            ("车身", [
                MoreItem(id: "trunk", title: "后备箱", icon: "car.side.rear.open", action: "trunk-open"),
                MoreItem(id: "frunk", title: "前备箱", icon: "car.side.front.open", action: "frunk-open"),
                MoreItem(id: "vent", title: "开窗通风", icon: "wind", action: "windows-vent"),
                MoreItem(id: "closewin", title: "关闭车窗", icon: "arrow.down.to.line", action: "windows-close"),
            ]),
            ("灯光与安全", [
                MoreItem(id: "flash", title: "闪灯找车", icon: "light.beacon.max", action: "flash"),
                MoreItem(id: "honk", title: "鸣笛", icon: "speaker.wave.2.fill", action: "honk"),
                MoreItem(id: "sentry-on", title: "开哨兵", icon: "shield.lefthalf.filled", action: "sentry-on"),
                MoreItem(id: "sentry-off", title: "关哨兵", icon: "shield.slash", action: "sentry-off"),
            ]),
            ("充电", [
                MoreItem(id: "port-open", title: "开充电口", icon: "bolt.car.fill", action: "charge-port-open"),
                MoreItem(id: "port-close", title: "关充电口", icon: "bolt.car", action: "charge-port-close"),
                MoreItem(id: "charge-start", title: "开始充电", icon: "play.fill", action: "charge-start"),
                MoreItem(id: "charge-stop", title: "停止充电", icon: "stop.fill", action: "charge-stop"),
            ]),
        ]
    }

    /// 统一的按钮外观（执行中会变暗 + 缩小）
    private func actionLabel(title: String, icon: String, active: Bool, enabled: Bool) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(active ? L.sand : L.text.opacity(0.45), lineWidth: 1)
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.app(15, .light))
                    .foregroundColor(active ? L.sand : L.text.opacity(0.9))
            }
            Text(title)
                .font(.app(11))
                .foregroundColor(active ? L.sand : L.text.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(L.card))
        .opacity(enabled ? 1 : 0.45)
        .scaleEffect(enabled ? 1 : 0.97)
        .animation(.easeOut(duration: 0.15), value: enabled)
    }


    // MARK: 充电卡

    private var chargingCard: some View {
        NavigationLink(destination: ChargeDetailView(api: api)) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.app(11))
                        .foregroundColor(L.sand)
                    Text("充电信息").font(.app(13, .medium)).foregroundColor(L.sub)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.app(10, .semibold))
                        .foregroundColor(L.dim)
                }
                let isChargingNow = (s?.charging ?? "").lowercased().contains("charging")
                let hasPower = (s?.chargerPower ?? 0) > 0
                if isChargingNow || hasPower {
                    // 充电中：功率 / 电压 / 电流（电压异常值不显示）
                    HStack(spacing: 0) {
                        metric(hasPower ? String(format: "%.1f", s!.chargerPower!) : "—", "功率 kW")
                        vDivider
                        metric((s?.chargerVoltage ?? 0) > 100 ? "\(Int(s!.chargerVoltage!))" : "—", "电压 V")
                        vDivider
                        metric((s?.chargerCurrent ?? 0) > 0 ? "\(Int(s!.chargerCurrent!))" : "—", "电流 A")
                    }
                } else {
                    // 未充电：显示上限 / 上次充入 / 剩余续航，比一排「—」有用
                    VStack(spacing: 6) {
                        HStack(spacing: 0) {
                            metric(s?.chargeLimit.map { "\($0)%" } ?? "—", "充电上限")
                            vDivider
                            metric("\(s?.battery ?? 0)%", "当前电量")
                            vDivider
                            metric("\(s?.rangeKm ?? 0)", "续航 km")
                        }
                        if let caption = lastChargeCaption {
                            Text(caption)
                                .font(.app(10))
                                .foregroundColor(L.dim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // 状态行：充电口 / 空调设定温度 / 预计充满
                HStack(spacing: 6) {
                    statusPill(icon: (s?.chargePortOpen ?? false) ? "bolt.car.fill" : "bolt.car",
                               text: (s?.chargePortOpen ?? false) ? "充电口已开" : "充电口关闭",
                               active: s?.chargePortOpen ?? false)
                    if let t = s?.setTemp, s?.climateOn == true {
                        statusPill(icon: "thermometer.snowflake",
                                   text: "空调 \(Int(t))°",
                                   active: true)
                    }
                    if let m = s?.minutesToFull, m > 0, (s?.charging ?? "").contains("Charging") {
                        statusPill(icon: "clock", text: "约 \(m) 分钟充满", active: false)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(L.card))
        }
        .buttonStyle(.plain)
    }

    // MARK: 手机钥匙（两个开关：靠近解锁 BLE / 离车上锁 云端）

    private var phoneKeyCard: some View {
        VStack(spacing: 0) {
            // 状态行
            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.app(20, .light))
                    .foregroundColor(L.text.opacity(0.9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("手机钥匙").font(.app(13, .medium)).foregroundColor(L.text)
                    Text(bleStatusText).font(.app(11)).foregroundColor(L.sub)
                }
                Spacer()
                Button { showBleLog = true } label: {
                    Image(systemName: "chevron.right")
                        .font(.app(10, .semibold))
                        .foregroundColor(L.dim)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            Rectangle().fill(L.line).frame(height: 1).padding(.bottom, 10)

            // 靠近自动解锁（手机侧 BLE）
            toggleRow(title: "靠近自动解锁",
                      subtitle: "蓝牙 · 约 3 米内",
                      isOn: ble.autoUnlockEnabled) { on in
                ble.setAutoUnlock(on)
            }

            // 离车自动上锁（服务器侧）
            toggleRow(title: "离车自动上锁",
                      subtitle: "蓝牙即时 + 云端 \(api.recorder?.delaySec ?? 90) 秒兜底",
                      isOn: pendingAutoLock ?? api.autoLockEnabled) { on in
                ble.setAutoLock(on)                       // 手机侧 BLE 立即生效
                withAnimation(.easeOut(duration: 0.12)) { pendingAutoLock = on }
                Task {
                    await api.setAutoLock(on)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    withAnimation(.easeOut(duration: 0.15)) { pendingAutoLock = nil }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(L.card))
    }

    private func toggleRow(title: String, subtitle: String,
                           isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(12.5)).foregroundColor(L.text.opacity(0.9))
                Text(subtitle).font(.app(9.5)).foregroundColor(L.dim)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { on in
                    Haptics.selection()
                    action(on)
                }
            ))
            .labelsHidden()
            .tint(L.sand)
            .scaleEffect(0.8)
        }
        .padding(.vertical, 6)
    }

    private var bleStatusText: String {
        if ble.connected { return "已连接 · \(s?.locked == true ? "车辆已上锁" : "车辆已解锁")" }
        if ble.scanCount > 0 { return "搜索中 · 已扫描 \(ble.scanCount) 次" }
        return "后台待命中"
    }

    // MARK: 工具

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    /// 时长文案：没真实数据时显示「—」，不再假装 0:00
    private func durText(_ minutes: Int?, known: Bool?) -> String {
        guard let m = minutes, (known ?? (m > 0)) else { return "—" }
        if m <= 0 { return "—" }
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    // MARK: 自动刷新

    /// 前台每 30 秒刷新一次；命令执行中或后台时跳过
    private func startAutoRefresh() {
        stopAutoRefresh()
        scheduleNextRefresh()
    }

    /// 连续失败时指数退避：30 → 60 → 120 → 300 秒封顶；成功立刻回到 30 秒
    private var currentRefreshInterval: TimeInterval {
        let fails = api.consecutiveRefreshFailures
        guard fails > 0 else { return 30 }
        return min(30 * pow(2, Double(min(fails, 4))), 300)
    }

    private func scheduleNextRefresh() {
        autoTimer?.invalidate()
        let interval = currentRefreshInterval
        autoTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                if !api.busy { await api.refresh() }
                // 蓝牙连着就续一次「在场」信号（抑制自动锁 + 高频采集）
                if ble.connected {
                    let near = ble.lastRSSI >= -80
                    ble.logEvent("在场判定：\(near ? "在场" : "已离开")（rssi=\(ble.lastRSSI)，阈值 -80）")
                    await api.presence(present: near)
                } else {
                    await api.presence(present: false)
                }
                if api.consecutiveRefreshFailures > 0 {
                    ble.logEvent("刷新失败 \(api.consecutiveRefreshFailures) 次，\(Int(currentRefreshInterval)) 秒后重试")
                }
                scheduleNextRefresh()
            }
        }
        autoTimer?.tolerance = min(5, interval * 0.1)
    }

    private func stopAutoRefresh() {
        autoTimer?.invalidate()
        autoTimer = nil
    }

    // MARK: 顶部提示条

    private var toastBanner: some View {
        Group {
            if let t = toast {
                HStack(spacing: 8) {
                    if t.loading {
                        ProgressView().scaleEffect(0.7).tint(L.sand)
                    } else {
                        Image(systemName: t.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .font(.app(13))
                            .foregroundColor(t.isError ? Color(hex: 0xE5484D) : L.ringGreen)
                    }
                    Text(t.text)
                        .font(.app(11.5))
                        .foregroundColor(L.text)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if t.isError, t.kind == .command, api.lastFailedCommand != nil {
                        Button {
                            Haptics.tap()
                            toast = nil
                            Task { await api.retryLastCommand() }
                        } label: {
                            Text("重试")
                                .font(.app(11.5, .medium))
                                .foregroundColor(L.sand)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().stroke(L.sand.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(L.card2)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(t.isError ? Color(hex: 0xE5484D).opacity(0.35) : L.line, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 54)          // 避开状态栏/刘海
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { toast = nil } }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ text: String, error: Bool = false, loading: Bool = false,
                           kind: ToastInfo.Kind = .info) {
        withAnimation(.easeOut(duration: 0.18)) {
            toast = ToastInfo(text: text, isError: error, loading: loading, kind: kind)
        }
        guard !loading else { return }
        // 只有「命令失败」才给重试机会
        let retryable = error && kind == .command && api.lastFailedCommand != nil
        let delay: Double = error ? (retryable ? 9.0 : 5.0) : 2.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if toast?.text == text {
                withAnimation(.easeOut(duration: 0.2)) { toast = nil }
            }
        }
    }

    private func openCarInMaps() {
        guard let lat = s?.lat, let lon = s?.lon else {
            posAlert = "车辆位置暂不可用（车可能在睡眠或没有信号）"
            return
        }
        // 特斯拉给 WGS-84，Apple 地图在中国要 GCJ-02，否则偏移 300~500 米
        let g = CoordTransform.toGCJ(lat: lat, lon: lon)
        let url = URL(string: "https://maps.apple.com/?ll=\(g.lat),\(g.lon)&q=我的车")!
        UIApplication.shared.open(url)
    }
}

// MARK: - BLE 日志面板

struct BleLogSheet: View {
    @ObservedObject var ble: TeslaKey
    @Environment(\.presentationMode) var pm
    @State private var copied = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationView {
            ZStack {
                L.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle().fill(ble.connected ? L.green : L.dim).frame(width: 7, height: 7)
                            Text(ble.connected ? "已连接" : "未连接").font(.app(12)).foregroundColor(L.text)
                            Spacer()
                            Text("扫描 \(ble.scanCount) 次 · 信号 \(ble.lastRSSI)").font(.app(11)).foregroundColor(L.sub)
                        }
                        .padding(.bottom, 6)

                        ForEach(ble.events.prefix(60), id: \.self) { line in
                            Text(line)
                                .font(.appMono(10))
                                .foregroundColor(L.sub)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
            }
            .confirmationDialog("清空日志？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    ble.clearLog()
                    copied = false
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("会删除所有历史记录，不影响配对和钥匙功能。")
            }
            .navigationTitle("手机钥匙日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { pm.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button("自检") { ble.selfTest() }
                        Button(copied ? "已复制" : "复制") {
                            UIPasteboard.general.string = ble.exportLog()
                            copied = true
                        }
                        Button("清空", role: .destructive) {
                            showClearConfirm = true
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}


// 让 String 能直接用于 .alert(item:)
extension String: Identifiable {
    public var id: String { self }
}


struct ToastInfo: Equatable {
    enum Kind { case info, command, refresh }
    var text: String
    var isError: Bool
    var loading: Bool
    var kind: Kind = .info
}

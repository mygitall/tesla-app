import SwiftUI

struct HomeView: View {
    @ObservedObject var api: TeslaAPI
    @State private var showSettings = false
    @ObservedObject private var ble = TeslaKey.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var copied = false

    private var s: VehicleSummary? { api.summary }
    private var isCharging: Bool { (s?.charging ?? "").lowercased() == "charging" }

    var body: some View {
        NavigationView {
            ZStack {
                L.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        headerCard
                        chipRow
                        carArt
                        powerCardLink
                        todayCard
                        actionCard
                        bleCard
                        autoLockCard
                        Color.clear.frame(height: 90)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .refreshable { await api.refresh() }
        .task {
            ble.start()
            if api.summary == nil { await api.refresh() }
        }
        .onChange(of: scenePhase) { phase in
            // 进后台立刻断开蓝牙，避免把车拖醒
            if phase != .active { ble.goBackground() }
        }

        .sheet(isPresented: $showSettings) { SettingsSheet(api: api) }
    }

    // MARK: 顶部

    private var headerCard: some View {
        LCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s?.name ?? "我的特斯拉")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(L.text)
                        Text(num(s?.odometerKm) + " km")
                            .font(.system(size: 13))
                            .foregroundColor(L.sub)
                    }
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15))
                            .foregroundColor(L.sub)
                            .padding(9)
                            .background(Circle().fill(L.fill))
                    }
                }

                HStack(spacing: 8) {
                    Pill(value: "\(s?.battery ?? 0)%", label: "电量")
                    Pill(value: num(s?.rangeKm) + " km", label: "剩余里程")
                    Pill(value: String(format: "%.1f 度", s?.batteryKwh ?? 0), label: "剩余电量")
                }
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            Tag(icon: "☀️", text: tempText(s?.outsideTemp))
            Tag(icon: "🚗", text: tempText(s?.insideTemp))
            Spacer(minLength: 0)
            if s?.locked == true {
                Tag(icon: "🔒", text: "已锁车", color: L.green)
            } else if s?.locked == false {
                Tag(icon: "🔓", text: "未锁车", color: L.orange)
            }
            Tag(text: (s?.isOnline ?? false) ? "已唤醒" : "已休眠",
                color: (s?.isOnline ?? false) ? L.green : L.sub)
        }
    }

    // MARK: 车辆图

    private var carArt: some View {
        Group {
            if let ui = UIImage(named: "car") {
                Image(uiImage: ui).resizable().scaledToFit()
                    .frame(maxHeight: 113)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 74, weight: .ultraLight))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(white: 0.25), Color(white: 0.6)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    Text("把车辆图片命名为 car.png 放进 Assets 可替换")
                        .font(.system(size: 9)).foregroundColor(L.sub)
                }
                .frame(height: 100)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 电量 / 充电

    /// 首页那块可点击的电量 / 充电卡片
    private var powerCardLink: some View {
        NavigationLink(destination: ChargeDetailView(api: api)) {
            PowerCard(s: s, isCharging: isCharging)
        }
        .buttonStyle(.plain)
    }



    // MARK: 今日

    private var todayCard: some View {
        LCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 13)).foregroundColor(L.orange)
                    Text("今日").font(.system(size: 16, weight: .semibold)).foregroundColor(L.text)
                    Spacer()
                    legend(L.green, "行驶")
                    legend(L.orange, "充电")
                    legend(L.blue, "停车")
                }

                timeline

                NavigationLink(destination: TripsListView(api: api)) {
                    HStack(spacing: 8) {
                        TodayStatTile(String(format: "%.1f km", s?.today?.distanceKm ?? 0), "今日里程")
                        TodayStatTile(durText(s?.today?.driveMinutes), "驾驶时长")
                        TodayStatTile(String(format: "¥%.2f", s?.today?.cost ?? 0), "行驶花费")
                        TodayStatTile(String(format: "%.1f kWh", s?.today?.energyKwh ?? 0), "今日耗电")
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timeline: some View {
        GeometryReader { geo in
            let driveRatio = min(max(Double(s?.today?.driveMinutes ?? 0) / 1440.0, 0.02), 0.9)
            HStack(spacing: 0) {
                Rectangle().fill(L.green).frame(width: geo.size.width * driveRatio)
                Rectangle().fill(L.orange).frame(width: geo.size.width * 0.04)
                Rectangle().fill(L.blue)
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(t).font(.system(size: 10)).foregroundColor(L.sub)
        }
    }

    // MARK: 快捷操作

    private var actionCard: some View {
        LCard {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    actionBtn(s?.locked == true ? "解锁" : "锁车",
                              s?.locked == true ? "lock.open.fill" : "lock.fill",
                              s?.locked == true ? L.blue : L.green) {
                        Task { await api.command((s?.locked ?? false) ? "unlock" : "lock",
                                                 label: (s?.locked ?? false) ? "解锁" : "锁车") }
                    }
                    actionBtn((s?.climateOn ?? false) ? "关空调" : "开空调",
                              "snowflake",
                              (s?.climateOn ?? false) ? L.sub : L.green) {
                        Task { await api.command((s?.climateOn ?? false) ? "climate-off" : "climate-on",
                                                 label: "空调") }
                    }
                }
                actionBtn("无钥匙启动（云端）", "key.fill", L.orange) {
                    Task { await api.command("drive", label: "无钥匙启动") }
                }
                if let t = api.actionText {
                    Text(t).font(.system(size: 11)).foregroundColor(L.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func actionBtn(_ title: String, _ icon: String, _ tint: Color,
                           _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.12)))
            .foregroundColor(tint)
        }
        .buttonStyle(.plain)
        .disabled(api.busy || !(s?.commandsEnabled ?? false))
        .opacity((api.busy || !(s?.commandsEnabled ?? false)) ? 0.5 : 1)
    }

    // MARK: 手机钥匙

    private var bleCard: some View {
        LCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").font(.system(size: 13))
                        .foregroundColor(ble.connected ? L.green : L.sub)
                    Text("手机钥匙（蓝牙）").font(.system(size: 15, weight: .semibold))
                        .foregroundColor(L.text)
                    Spacer()
                    Text(ble.phase.rawValue).font(.system(size: 11))
                        .foregroundColor(ble.connected ? L.green : L.sub)
                }
                if !ble.detail.isEmpty {
                    Text(ble.detail).font(.system(size: 11))
                        .foregroundColor(ble.detail.hasPrefix("✓") ? L.green
                                          : ble.detail.hasPrefix("✗") ? Color.red : L.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 常驻诊断行：扫描次数 / 信号强度 / 最后发现时间
                HStack(spacing: 10) {
                    diagItem("扫描", "\(ble.scanCount) 次",
                             color: ble.scanCount > 0 ? L.green : L.orange)
                    diagItem("信号", ble.lastRSSI > -127 ? "\(ble.lastRSSI) dBm" : "—",
                             color: ble.lastRSSI >= -65 ? L.green
                                   : ble.lastRSSI >= -85 ? L.orange : L.sub)
                    diagItem("最后发现", seenText(ble.lastSeenAt), color: L.sub)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(L.fill))

                // 蓝牙事件日志（最近 8 条）
                if !ble.events.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 12) {
                            Text("蓝牙事件日志").font(.system(size: 10, weight: .semibold))
                                .foregroundColor(L.sub)
                            Spacer()
                            Button(copied ? "已复制 ✓" : "复制") {
                                UIPasteboard.general.string = ble.exportLog()
                                copied = true
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    copied = false
                                }
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(copied ? L.green : L.blue)

                            Button("清空") { ble.events.removeAll()
                                UserDefaults.standard.removeObject(forKey: "bleEvents") }
                                .font(.system(size: 10)).foregroundColor(L.sub)
                        }
                        ForEach(ble.events.prefix(8), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(L.text.opacity(0.75))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06)))
                }
                Text("蓝牙状态 raw=\(ble.centralStateRaw)（5 才正常）· 附近设备 \(ble.nearbyCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(ble.centralStateRaw == 5 ? L.green : L.orange)

                HStack(spacing: 8) {
                    bleBtn("诊断扫描", "dot.radiowaves.left.and.right", L.orange, alwaysOn: true) { ble.startDiagnosticScan() }
                    bleBtn("解锁", "lock.open.fill", L.blue) { ble.unlock() }
                    bleBtn("上锁", "lock.fill", L.green) { ble.lock() }
                    bleBtn("启动", "car.fill", L.orange) { ble.drive() }
                }
            }
        }
    }

    private func diagItem(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundColor(color)
            Text(label).font(.system(size: 9)).foregroundColor(L.sub)
        }
        .frame(maxWidth: .infinity)
    }

    private func seenText(_ date: Date?) -> String {
        guard let date else { return "从未" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "刚刚" }
        if s < 60 { return "\(s) 秒前" }
        if s < 3600 { return "\(s / 60) 分钟前" }
        return "\(s / 3600) 小时前"
    }

    private func bleBtn(_ t: String, _ i: String, _ c: Color,
                        alwaysOn: Bool = false,
                        _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 4) {
                Image(systemName: i).font(.system(size: 15))
                Text(t).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.opacity(0.12)))
            .foregroundColor(c)
        }
        .buttonStyle(.plain)
        .disabled(!alwaysOn && !ble.connected)
        .opacity((alwaysOn || ble.connected) ? 1 : 0.4)
    }

    // MARK: 自动锁

    private var autoLockCard: some View {
        LCard {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { api.autoLockEnabled },
                    set: { v in Task { await api.setAutoLock(v) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("离车自动上锁").font(.system(size: 15, weight: .semibold))
                            .foregroundColor(L.text)
                        Text(api.autoLockEnabled
                             ? "已开启 · 离车未锁 60 秒后上锁"
                             : "已关闭")
                            .font(.system(size: 11)).foregroundColor(L.sub)
                    }
                }
                .tint(L.green)

                Divider().padding(.vertical, 2)

                Toggle(isOn: Binding(
                    get: { ble.autoUnlockEnabled },
                    set: { v in ble.setAutoUnlock(v) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("走近自动解锁").font(.system(size: 15, weight: .semibold))
                            .foregroundColor(L.text)
                        Text(ble.autoUnlockEnabled
                             ? "已开启 · 后台等待车辆蓝牙，靠近自动解锁"
                             : "已关闭")
                            .font(.system(size: 11)).foregroundColor(L.sub)
                    }
                }
                .tint(L.blue)

                Text("后台监听车辆蓝牙广播，信号达到 -65dBm（约 3~5 米）才连接并解锁，解锁后 20 秒自动断开。不需要定位权限，也不耗车辆电量。")
                    .font(.system(size: 10)).foregroundColor(L.sub)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().padding(.vertical, 2)

                Text("云端实现：检测驾驶座无人 + 未上锁 + P 档 + 六门全关，持续 60 秒后自动锁车。手机不在附近也会生效。")
                    .font(.system(size: 10)).foregroundColor(L.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 工具

    private func num(_ v: Int?) -> String {
        guard let v else { return "—" }
        return NumberFormatter.localizedString(from: NSNumber(value: v), number: .decimal)
    }

    private func tempText(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.1f℃", v)
    }

    private func durText(_ m: Int?) -> String {
        guard let m, m > 0 else { return "0 分" }
        return m >= 60 ? "\(m / 60) 时 \(m % 60) 分" : "\(m) 分"
    }
}

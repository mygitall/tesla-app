import SwiftUI
import UIKit

/// 首页 · 高端深色风（按参考稿实测还原）
struct HomeView: View {
    @ObservedObject var api: TeslaAPI
    @ObservedObject private var ble = TeslaKey.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showBleLog = false

    private var s: VehicleSummary? { api.summary }
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
                        carSection
                        batteryCard
                        todayCard
                        actionRow
                        chargingCard
                        phoneKeyCard
                        Color.clear.frame(height: 96)
                    }
                    .padding(.horizontal, hPad)
                    .padding(.top, 4)
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
            if phase != .active { ble.goBackground() }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(api: api) }
        .sheet(isPresented: $showBleLog) { BleLogSheet(ble: ble) }
    }

    // MARK: 背景（顶部暖色光晕）

    private var background: some View {
        ZStack(alignment: .top) {
            L.bg.ignoresSafeArea()
            RadialGradient(
                colors: [L.glow.opacity(0.55), L.bg.opacity(0)],
                center: .top, startRadius: 10, endRadius: 380
            )
            .frame(height: 420)
            .ignoresSafeArea()
        }
    }

    // MARK: 标题

    private var titleBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TESLA MODEL Y")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(5)
                    .foregroundColor(L.text)
                Text("特斯拉 Model Y 标准续航版")
                    .font(.system(size: 11))
                    .foregroundColor(L.sub)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .light))
                    .foregroundColor(L.text.opacity(0.85))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
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
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundColor(L.text.opacity(0.25))
                    .frame(height: 110)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: 电量卡

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(s?.battery ?? 0)")
                    .font(.system(size: 46, weight: .light))
                    .monospacedDigit()
                    .foregroundColor(L.text)
                Text("%")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(L.sub)
            }
            Text("续航 \(s?.rangeKm ?? 0) km")
                .font(.system(size: 12))
                .foregroundColor(L.sub)
            progressBar.padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(L.card))
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let pct = min(max(Double(s?.battery ?? 0) / 100, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule().fill(L.sand).frame(width: geo.size.width * pct)
            }
        }
        .frame(height: 3)
    }

    // MARK: 今日卡

    private var todayCard: some View {
        NavigationLink(destination: TripsListView(api: api)) {
            VStack(spacing: 10) {
                HStack {
                    Text("今日行程").font(.system(size: 13, weight: .medium)).foregroundColor(L.sub)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(L.dim)
                }
                HStack(spacing: 0) {
                    metric(String(format: "%.1f", s?.today?.distanceKm ?? 0), "km")
                    vDivider
                    metric(durText(s?.today?.driveMinutes), "小时")
                    vDivider
                    metric(String(format: "%.0f", s?.today?.energyKwh ?? 0), "kWh")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(L.card))
        }
        .buttonStyle(.plain)
    }

    private func metric(_ v: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v)
                .font(.system(size: 23, weight: .regular))
                .monospacedDigit()
                .foregroundColor(L.text)
            Text(unit)
                .font(.system(size: 11))
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
            actionButton(title: (s?.locked ?? true) ? "解锁" : "上锁",
                         icon: (s?.locked ?? true) ? "lock.open" : "lock") {
                let locked = s?.locked ?? true
                Task { await api.command(locked ? "unlock" : "lock", label: locked ? "解锁" : "上锁") }
            }
            actionButton(title: "启动", icon: "key") {
                Task { await api.command("drive", label: "无钥匙启动") }
            }
            actionButton(title: "空调", icon: "fanblades",
                         active: s?.climateOn == true) {
                let on = s?.climateOn ?? false
                Task { await api.command(on ? "climate-off" : "climate-on", label: on ? "关空调" : "开空调") }
            }
            actionButton(title: "定位", icon: "location") {
                openCarInMaps()
            }
        }
    }

    private func actionButton(title: String, icon: String, active: Bool = false, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .stroke(active ? L.sand : L.text.opacity(0.45), lineWidth: 1)
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .light))
                        .foregroundColor(active ? L.sand : L.text.opacity(0.9))
                }
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(L.text.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(L.card))
        }
        .buttonStyle(.plain)
    }

    // MARK: 充电卡

    private var chargingCard: some View {
        NavigationLink(destination: ChargeDetailView(api: api)) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                        .foregroundColor(L.sand)
                    Text("充电信息").font(.system(size: 13, weight: .medium)).foregroundColor(L.sub)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(L.dim)
                }
                HStack(spacing: 0) {
                    metric((s?.chargerPower ?? 0) > 0 ? String(format: "%.1f", s!.chargerPower!) : "—", "功率 kW")
                    vDivider
                    metric((s?.chargerVoltage ?? 0) > 50 ? "\(Int(s!.chargerVoltage!))" : "—", "电压 V")
                    vDivider
                    metric((s?.chargerCurrent ?? 0) > 0 ? "\(Int(s!.chargerCurrent!))" : "—", "电流 A")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(L.card))
        }
        .buttonStyle(.plain)
    }

    // MARK: 手机钥匙

    private var phoneKeyCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(L.text.opacity(0.9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("手机钥匙").font(.system(size: 13, weight: .medium)).foregroundColor(L.text)
                    Text(bleStatusText).font(.system(size: 11)).foregroundColor(L.sub)
                }
                Spacer()
                Button { showBleLog = true } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(L.dim)
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("离车自动上锁").font(.system(size: 12)).foregroundColor(L.sub)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { api.autoLockEnabled },
                    set: { on in Task { await api.setAutoLock(on) } }
                ))
                .labelsHidden()
                .tint(L.sand)
                .scaleEffect(0.85)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(L.card))
    }

    private var bleStatusText: String {
        if ble.connected { return "已连接 · \(s?.locked == true ? "车辆已上锁" : "车辆已解锁")" }
        if ble.scanCount > 0 { return "搜索中 · 已扫描 \(ble.scanCount) 次" }
        return "后台待命中"
    }

    // MARK: 工具

    private func durText(_ minutes: Int?) -> String {
        let m = minutes ?? 0
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    private func openCarInMaps() {
        guard let lat = s?.lat, let lon = s?.lon else { return }
        let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)&q=我的车")!
        UIApplication.shared.open(url)
    }
}

// MARK: - BLE 日志面板

struct BleLogSheet: View {
    @ObservedObject var ble: TeslaKey
    @Environment(\.presentationMode) var pm
    @State private var copied = false

    var body: some View {
        NavigationView {
            ZStack {
                L.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle().fill(ble.connected ? L.green : L.dim).frame(width: 7, height: 7)
                            Text(ble.connected ? "已连接" : "未连接").font(.system(size: 12)).foregroundColor(L.text)
                            Spacer()
                            Text("扫描 \(ble.scanCount) 次 · 信号 \(ble.lastRSSI)").font(.system(size: 11)).foregroundColor(L.sub)
                        }
                        .padding(.bottom, 6)

                        ForEach(ble.events.prefix(60), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(L.sub)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("手机钥匙日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { pm.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(copied ? "已复制" : "复制") {
                        UIPasteboard.general.string = ble.exportLog()
                        copied = true
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

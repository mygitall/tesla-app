import Foundation
import CoreBluetooth
import CryptoKit
import TeslaBLE

/// 真 BLE 手机钥匙：CoreBluetooth 负责收发，加密/签名交给 Go 框架
@MainActor
final class TeslaKey: NSObject, ObservableObject {

    enum Phase: String {
        case idle = "未启动"
        case scanning = "搜索车辆…"
        case connecting = "连接中…"
        case securing = "建立加密会话…"
        case ready = "已连接"
        case failed = "失败"
    }

    @Published var phase: Phase = .idle
    @Published var detail: String = ""
    @Published var connected = false
    @Published var lastRSSI: Int = -127
    /// 最近信号来自哪辆车（用于诊断）
    @Published var lastRSSISource: String = "-"
    /// 已确认的车辆外设 ID（后台没有 broadcast name 时靠它认出本车）
    private var myPeripheralID: UUID? {
        get {
            guard let s = UserDefaults.standard.string(forKey: "myCarPeripheralID") else { return nil }
            return UUID(uuidString: s)
        }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "myCarPeripheralID") }
    }
    /// 记录过的其他车辆名，避免重复刷日志
    private var foreignNames = Set<String>()
    /// 上次自动解锁时间（冷却，避免反复解锁）
    private var lastAutoUnlockAt: Date?
    /// 蓝牙离车上锁（手机侧执行，比云端快）
    @Published var autoLockEnabled: Bool =
        (UserDefaults.standard.object(forKey: "bleAutoLock") as? Bool) ?? true
    private var wasNear = false           // 当前是否在车边（信号够强）
    private var cameNearFlag = false      // 本轮是否发生了「远→近」跨越
    private var farSince: Date?           // 变远开始计时
    private var lastAutoLockAt: Date?     // 上锁冷却
    private var autoLockTask: Task<Void, Never>?
    /// 本次断开是不是 App 主动发起的（后台/空闲），主动断开不能触发上锁
    private var intentionalDisconnect = false
    static let autoUnlockCooldown: TimeInterval = 45      // 只防抖，不防「离开再回来」
    @Published var scanCount = 0          // 扫到过几次
    @Published var events: [String] = []   // 蓝牙事件日志（持久化）
    @Published var centralStateRaw: Int = -1
    @Published var nearbyCount = 0          // 不加 UUID 过滤时看到的设备数
    @Published var diagnosticDone = false
    private var diagnosticMode = false
    private var lastPhaseKey = ""
    private var diagLogged = 0
    private var keepAlive: Task<Void, Never>?
    private var lastDiscoveryLog = 0.0
    @Published var lastSeenAt: Date?
    @Published var autoUnlockEnabled: Bool =
        (UserDefaults.standard.object(forKey: "bleAutoUnlock") as? Bool) ?? true

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var txChar: CBCharacteristic?
    private var session: MobilebridgeSession?

    private var rxBuffer = Data()
    private let vin: String
    private let keyPEM: String
    private var pumpTask: Task<Void, Never>?
    private var pendingAction: (() -> Void)?     // 连上后要执行的动作
    private var idleDisconnect: Task<Void, Never>? // 空闲断开计时

    /// 全局单例：不依赖登录状态，离线也能自动开关门
    static let shared = TeslaKey(vin: BLEConfig.vin, keyPEM: BLEConfig.keyPEM)

    /// 自动解锁的信号阈值：≥ -65dBm ≈ 3~5 米内
    static let autoUnlockRSSI = -75

    /// 车辆「广播」里带的服务 UUID —— 实测是 0x1122，不是 0x0211
    static let advServiceUUID = CBUUID(string: "1122")

    /// 连接后才用的 GATT 服务 UUID
    static let serviceUUID = CBUUID(string: "00000211-B2D1-43F0-9B88-960CEBF8B91E")
    static let toVehicleUUID = CBUUID(string: "00000212-B2D1-43F0-9B88-960CEBF8B91E")
    static let fromVehicleUUID = CBUUID(string: "00000213-B2D1-43F0-9B88-960CEBF8B91E")

    init(vin: String, keyPEM: String) {
        self.vin = vin
        self.keyPEM = keyPEM
        super.init()
        self.events = UserDefaults.standard.stringArray(forKey: "bleEvents") ?? []
    }

    /// 记录一条蓝牙事件（会持久化，App 被系统杀掉也不丢）
    /// 清空事件日志
    func clearLog() {
        events.removeAll()
        UserDefaults.standard.removeObject(forKey: "bleEvents")
        logEvent("日志已清空")
    }

    func logEvent(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "\(f.string(from: Date()))  \(text)"
        events.insert(line, at: 0)
        if events.count > 40 { events.removeLast(events.count - 40) }
        UserDefaults.standard.set(events, forKey: "bleEvents")
    }

    /// 车辆广播名：S + sha1(vin)[0..8] 十六进制 + C
    static func localName(for vin: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(vin.utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "S\(hex)C"
    }

    // MARK: 启动

    /// 回到前台：复位「在车边」状态，让第一次强信号被当作「刚走近」→ 可以解锁
    func appForegrounded() {
        wasNear = false
        cameNearFlag = false
        start()
    }

    func start() {
        guard central == nil else {
            if central?.state == .poweredOn, peripheral == nil { beginScan() }
            return
        }
        // 带恢复标识：即使 App 被系统回收，iOS 也能因蓝牙事件把它拉起来
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "tesla-car-central"]
        )
    }

    func stop() {
        keepAlive?.cancel(); keepAlive = nil
        pumpTask?.cancel(); pumpTask = nil
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        session?.close(); session = nil
        peripheral = nil; txChar = nil; rxBuffer = Data()
        connected = false
        phase = .idle
    }

    private func beginScan(filtered: Bool = true) {
        logEvent(filtered ? "开始扫描（UUID过滤）" : "开始扫描（全部设备）")
        phase = .scanning
        detail = "搜索车辆中…（已扫描 \(scanCount) 次）"
        let services: [CBUUID]? = filtered ? [Self.advServiceUUID] : nil
        central?.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: autoUnlockEnabled]
        )
    }

    // MARK: 指令

    func unlock() { request("解锁") { $0.unlock() } }
    func lock()   { request("上锁") { $0.lock() } }
    func drive()  { request("无钥匙启动") { $0.drive() } }

    /// 导出完整日志文本（用于复制/粘贴给开发者）
    func exportLog() -> String {
        var out: [String] = []
        out.append("=== Tesla BLE 诊断 ===")
        out.append("时间: \(Date())")
        out.append("VIN: \(vin)")
        out.append("蓝牙状态 raw: \(centralStateRaw)  （0未知 1重置 2不支持 3无权限 4关闭 5已开启）")
        out.append("扫描次数: \(scanCount)   附近设备: \(nearbyCount)")
        out.append("本车广播名: \(Self.localName(for: vin))")
        out.append("本车识别: \(myPeripheralID == nil ? "尚未确认（等一次成功会话）" : "已记住外设 ID")")
        out.append("最近信号: \(lastRSSI) dBm（来源：\(lastRSSISource)）")
        out.append("自动解锁: \(autoUnlockEnabled ? "开" : "关")   自动解锁阈值: \(Self.autoUnlockRSSI) dBm")
        out.append("忽略的其他车辆: \(foreignNames.isEmpty ? "无" : foreignNames.sorted().joined(separator: ", "))")
        out.append("状态: \(phase.rawValue) / \(detail)")
        out.append("— 关键判定 —")
        out.append("  · 在场阈值 -80 dBm：当前 \(lastRSSI >= -80 ? "在场" : "已离开")（\(lastRSSI) dBm）")
        out.append("  · 解锁阈值 \(Self.autoUnlockRSSI) dBm：当前 \(lastRSSI >= Self.autoUnlockRSSI ? "够强" : "不够")")
        out.append("--- 事件日志（新→旧）---")
        out.append(contentsOf: events)
        return out.joined(separator: "\n")
    }

    /// 后台保活：周期性重启扫描。iOS 会节流后台 BLE，
    /// 重启扫描能强制系统持续回调，避免"走近了没反应"。
    private func startKeepAlive() {
        keepAlive?.cancel()
        keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self, self.autoUnlockEnabled else { break }
                await MainActor.run {
                    guard let c = self.central, c.state == .poweredOn else { return }
                    c.stopScan()
                    self.beginScan(filtered: true)
                }
            }
        }
    }

    /// 诊断用：不加 UUID 过滤，扫描 15 秒，记录所有像特斯拉的广播
    func startDiagnosticScan() {
        if central == nil { start() }      // 保证蓝牙已初始化
        nearbyCount = 0
        diagnosticMode = true
        diagLogged = 0
        logEvent("=== 诊断扫描开始（全部设备，15 秒）===")
        beginScan(filtered: false)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self else { return }
            self.diagnosticMode = false
            self.diagnosticDone = true
            self.logEvent("=== 诊断结束，共看到 \(self.nearbyCount) 个设备 ===")
            // 自动解锁开着才恢复过滤扫描，否则停下省电
            if self.autoUnlockEnabled { self.beginScan(filtered: true) }
            else { self.central?.stopScan(); self.phase = .idle; self.detail = "诊断完成" }
        }
    }

    /// 打开/关闭「走近自动解锁」
    func setAutoLock(_ on: Bool) {
        autoLockEnabled = on
        UserDefaults.standard.set(on, forKey: "bleAutoLock")
        logEvent("蓝牙离车上锁：\(on ? "开" : "关")")
        if !on { cancelAutoLock() }
    }

    /// 每次扫到本车时评估：走远了就安排 BLE 上锁
    private func evaluateBleAutoLock(rssi: Int) {
        guard autoLockEnabled else { return }
        if rssi >= -75 {
            wasNear = true
            farSince = nil
            cancelAutoLock()
            return
        }
        guard wasNear, rssi <= -85 else {
            if rssi <= -85 { wasNear = false }   // 走远 → 复位，下次靠近可再触发
            return
        }
        if farSince == nil {
            farSince = Date()
            logEvent("信号变弱（\(rssi)dBm），15 秒后若仍未靠近则上锁")
        }
        guard let since = farSince, Date().timeIntervalSince(since) >= 15 else { return }
        guard autoLockTask == nil else { return }
        if let t = lastAutoLockAt, Date().timeIntervalSince(t) < 300 { return }
        scheduleBleLock(reason: "走远 \(rssi)dBm")
    }

    /// 蓝牙断开也视为离开
    private func evaluateBleAutoLockOnDisconnect() {
        guard autoLockEnabled, wasNear else { return }
        guard autoLockTask == nil else { return }
        if let t = lastAutoLockAt, Date().timeIntervalSince(t) < 300 { return }
        scheduleBleLock(reason: "蓝牙断开")
    }

    private func scheduleBleLock(reason: String) {
        if let u = lastAutoUnlockAt, Date().timeIntervalSince(u) < 120 {
            logEvent("跳过蓝牙上锁：刚解锁 \(Int(Date().timeIntervalSince(u))) 秒")
            return
        }
        lastAutoLockAt = Date()
        logEvent("安排蓝牙上锁（\(reason)）")
        pendingAction = { [weak self] in
            self?.run("自动上锁") { $0.lock() }
        }
        if let p = peripheral {
            autoLockTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.central?.stopScan()
                    self.phase = .connecting
                    self.logEvent("发起连接（上锁）rssi=\(self.lastRSSI)")
                    self.central?.connect(p, options: nil)
                    self.autoLockTask = nil
                }
            }
        }
    }

    private func cancelAutoLock() {
        autoLockTask?.cancel()
        autoLockTask = nil
        if pendingAction != nil { pendingAction = nil }
    }

    func setAutoUnlock(_ on: Bool) {
        lastPhaseKey = "fg"
        autoUnlockEnabled = on
        UserDefaults.standard.set(on, forKey: "bleAutoUnlock")
        if on {
            detail = "已开启：后台持续等待车辆蓝牙"
            beginScan()
            startKeepAlive()
        } else {
            keepAlive?.cancel(); keepAlive = nil
            detail = "已关闭自动解锁"
        }
    }

    /// 地理围栏触发：开始被动扫描，扫到且信号够强才连（didDiscover 里有 -80 门控）
    func beginProximityUnlock() {
        cancelIdleDisconnect()
        detail = "已到车附近，等待蓝牙信号…"
        phase = .scanning
        pendingAction = { [weak self] in self?.run("解锁") { $0.unlock() } }
        beginScan()
    }

    /// 兼容旧调用
    func autoUnlockIfNear() { beginProximityUnlock() }

    /// 离开车辆范围：上锁并断开
    func autoLockAndDisconnect() {
        guard session != nil else { disconnectNow(reason: "已离开车辆范围"); return }
        request("上锁") { $0.lock() }
    }

    /// 需要操作时才建立连接
    private func request(_ label: String, _ action: @escaping (MobilebridgeSession) -> Bool) {
        cancelIdleDisconnect()
        if session != nil {
            run(label, action)
            scheduleIdleDisconnect()
            return
        }
        // 记下待办动作，然后开始扫描
        pendingAction = { [weak self] in self?.run(label, action) }
        if let p = peripheral, p.state == .connected {
            startSession()
        } else {
            beginScan()
        }
    }

    /// 空闲 20 秒后主动断开，让车可以休眠
    private func scheduleIdleDisconnect() {
        cancelIdleDisconnect()
        idleDisconnect = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.disconnectNow(reason: "空闲断开，让车休眠") }
        }
    }

    private func cancelIdleDisconnect() {
        idleDisconnect?.cancel(); idleDisconnect = nil
    }

    /// 主动断开蓝牙连接
    func disconnectNow(reason: String) {
        intentionalDisconnect = true
        cancelIdleDisconnect()
        pumpTask?.cancel(); pumpTask = nil
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        session?.close(); session = nil
        rxBuffer = Data()
        logEvent("断开：\(reason)")
        connected = false
        phase = .idle
        detail = reason
        if autoUnlockEnabled, let c = central, c.state == .poweredOn {
            beginScan()
        }
    }

    /// App 进入后台：断开连接；但如果开了自动解锁，保持被动扫描
    func goBackground() {
        if lastPhaseKey != "bg" { logEvent("App 进入后台"); lastPhaseKey = "bg" }
        cancelIdleDisconnect()
        if session != nil {
            logEvent("后台：等动作完成后再断开")
            idleDisconnect = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.disconnectNow(reason: "App 在后台") }
            }
            return
        }
        disconnectNow(reason: "App 在后台")
        if autoUnlockEnabled {
            // 关键：后台保持扫描，服务 UUID 过滤，iOS 允许并会在发现时唤醒 App
            beginScan(filtered: true)
            detail = "后台待命中（已扫描 \(scanCount) 次）"
        } else {
            central?.stopScan()
        }
    }

    private func run(_ label: String, _ action: @escaping (MobilebridgeSession) -> Bool) {
        guard let s = session else { detail = "还没连上车辆"; return }
        detail = "\(label)中…"
        Task {
            // Go 侧是阻塞调用，放到后台线程，完成后回到主线程更新 UI
            var ok = await Task.detached(priority: .userInitiated) { action(s) }.value
            var err = s.lastError()

            if !ok {
                logEvent("\(label) 首次失败：\(err)，2 秒后重试")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                ok = await Task.detached(priority: .userInitiated) { action(s) }.value
                err = s.lastError()
            }

            logEvent("\(label)：\(ok ? "成功 ✅" : "失败 ❌ \(err)")")
            detail = ok ? "✓ \(label)成功" : "✗ \(err.isEmpty ? "失败" : err)"
        }
    }
}

// MARK: - CoreBluetooth

extension TeslaKey: CBCentralManagerDelegate, CBPeripheralDelegate {

    nonisolated func centralManager(_ central: CBCentralManager,
                                    willRestoreState dict: [String: Any]) {
        // 系统因蓝牙事件把 App 拉起来：接着扫描
        Task { @MainActor in
            if self.autoUnlockEnabled { self.beginScan() }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let raw = central.state.rawValue
        Task { @MainActor in
            self.centralStateRaw = raw
            self.logEvent("蓝牙状态 raw=\(raw)（0未知 1重置 2不支持 3无权限 4关闭 5已开启）")
            switch central.state {
            case .poweredOn:
                self.phase = .idle
                if self.autoUnlockEnabled {
                    self.beginScan()
                    self.detail = "后台待命中（等待车辆蓝牙）"
                } else {
                    self.detail = "蓝牙就绪，点按钮连接车辆"
                }
            case .unauthorized:
                self.phase = .failed
                self.detail = "蓝牙权限被拒绝，请到设置里开启"
            case .poweredOff:
                self.phase = .failed
                self.detail = "蓝牙未开启"
            default:
                self.phase = .failed
                self.detail = "蓝牙状态 \(central.state.rawValue)"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let name = advName ?? peripheral.name ?? ""
        Task { @MainActor in
            // iOS 后台不会给 local name，所以只认「广播里带特斯拉服务 UUID」。
            // 扫描本身已按该 UUID 过滤，走到这里基本就是我们的车。
            self.nearbyCount += 1
            let rssi = RSSI.intValue
            let svcText = services.map { $0.uuidString.prefix(8) }.joined(separator: ",")
            // 诊断模式：记录所有近距离、有名字的设备（方便找到车）
            if self.diagnosticMode, rssi >= -85, !name.isEmpty, self.diagLogged < 40 {
                self.diagLogged += 1
                self.logEvent("设备: \(name) svc=[\(svcText.isEmpty ? "无" : svcText)] rssi=\(rssi)")
            }
            // 平时只记录像特斯拉的
            let looksTesla = name.hasPrefix("S")
                || services.contains(Self.serviceUUID)
                || services.contains(Self.advServiceUUID)
            if looksTesla && !self.diagnosticMode {
                self.logEvent("广播: name=\(name.isEmpty ? "无" : name) svc=[\(svcText)] rssi=\(rssi)")
            }

            let byUUID = services.contains(Self.serviceUUID)
                || services.contains(Self.advServiceUUID)
            let myName = Self.localName(for: self.vin)
            let byName = !name.isEmpty && name == myName
            guard byUUID || byName else { return }

            // ── 关键：区分「本车」和「邻居的车」 ──
            // 所有特斯拉都广播 1122，只靠 UUID 会把邻居车当成本车，
            // 导致：信号取错（以为你走远了）、连到别人车上（配对失败）。
            var identity = "?"
            let isMine: Bool
            if !name.isEmpty {
                isMine = (name == myName)
                identity = "名字"
                if !isMine {
                    if self.foreignNames.insert(name).inserted {
                        self.logEvent("跳过其他车辆 name=\(name) rssi=\(rssi)")
                    }
                    return
                }
            } else if let known = self.myPeripheralID {
                isMine = (peripheral.identifier == known)
                identity = "已记住的外设ID"
                if !isMine { return }
            } else {
                // 后台拿不到名字、也还没记住本车 → 只能赌一次
                isMine = true
                identity = "未知（首次，靠配对结果确认）"
            }
            guard isMine else { return }

            if !self.wasNear, rssi >= Self.autoUnlockRSSI { self.cameNearFlag = true }
            self.evaluateBleAutoLock(rssi: rssi)
            self.lastRSSI = rssi
            self.lastRSSISource = "\(name.isEmpty ? "无名字" : name)（识别方式：\(identity)）"
            self.scanCount += 1
            self.lastSeenAt = Date()
            // 日志去重：信号没大变就不重复记
            let now = Date().timeIntervalSince1970
            if now - self.lastDiscoveryLog > 3 || abs(rssi - self.lastRSSI) >= 5 {
                self.lastDiscoveryLog = now
                self.logEvent("发现设备 rssi=\(rssi)")
            }
            self.peripheral = peripheral
            peripheral.delegate = self
            self.detail = "发现车辆（信号 \(rssi)dBm）"

            // 开了自动解锁 + 信号够强 + 「刚走近」（不是一直站着） → 解锁
            let cooled = self.lastAutoUnlockAt.map { Date().timeIntervalSince($0) >= Self.autoUnlockCooldown } ?? true
            let cameNear = self.cameNearFlag
            self.cameNearFlag = false
            if self.pendingAction == nil, self.autoUnlockEnabled, rssi >= Self.autoUnlockRSSI, cameNear, cooled {
                self.lastAutoUnlockAt = Date()
                self.logEvent("安排自动解锁（rssi=\(rssi)，来自「远→近」跨越）")
                self.pendingAction = { [weak self] in
                    self?.run("自动解锁") { $0.unlock() }
                }
                self.detail = "检测到车辆（\(rssi)dBm），自动解锁中…"
            }

            if !self.cameNearFlag, self.autoUnlockEnabled, rssi >= Self.autoUnlockRSSI,
               self.pendingAction == nil, !cooled {
                let left = Self.autoUnlockCooldown - Date().timeIntervalSince(self.lastAutoUnlockAt ?? Date())
                self.logEvent("跳过自动解锁：冷却中（还需 \(Int(max(0,left))) 秒）")
            }

            // 没有待执行动作就【不连接】——避免后台挂着蓝牙把车拖醒
            guard self.pendingAction != nil else {
                central.stopScan()
                self.phase = .idle
                self.detail = "车在附近（未连接，点按钮才连）"
                return
            }
            // 信号太弱说明还远，继续扫描等靠近
            if rssi < -80 {
                self.detail = "信号 \(rssi)dBm，还太远，等待靠近…"
                // 继续等下一次重复上报，不立刻连接
                if self.autoUnlockEnabled {
                    // iOS 后台不给重复上报，重启一次扫描以获取新的信号值
                    central.stopScan()
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if self.autoUnlockEnabled { self.beginScan() }
                }
                return
            }
            central.stopScan()
            self.logEvent("发起连接 rssi=\(rssi)")
            self.phase = .connecting
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.logEvent("已连接，发现服务")
            self.phase = .connecting
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            if self.intentionalDisconnect {
                self.intentionalDisconnect = false
                self.logEvent("断开是 App 主动发起的，不触发离车上锁")
            } else {
                self.evaluateBleAutoLockOnDisconnect()
            }
        }
        Task { @MainActor in
            self.logEvent("连接已断开\(error.map { "：\($0.localizedDescription)" } ?? "")")
            self.connected = false
            self.session?.close(); self.session = nil
            if self.autoUnlockEnabled { self.beginScan() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.logEvent("连接失败：\(error?.localizedDescription ?? "未知")")
            self.phase = .failed
            self.detail = "连接失败：\(error?.localizedDescription ?? "未知")"
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let svc = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
                self.phase = .failed; self.detail = "没找到车辆服务"; return
            }
            peripheral.discoverCharacteristics([Self.toVehicleUUID, Self.fromVehicleUUID], for: svc)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            for c in service.characteristics ?? [] {
                if c.uuid == Self.toVehicleUUID { self.txChar = c }
                if c.uuid == Self.fromVehicleUUID { peripheral.setNotifyValue(true, for: c) }
            }
            guard self.txChar != nil else {
                self.phase = .failed; self.detail = "没找到写入通道"; return
            }
            self.startSession()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in self.ingest(data) }
    }
}

// MARK: - 分帧 + 泵

private extension TeslaKey {

    func startSession() {
        phase = .securing
        do {
            var err: NSError?
            guard let s = MobilebridgeNewSession(vin, keyPEM, &err) else {
                phase = .failed
                detail = "加载私钥失败：\(err?.localizedDescription ?? "未知")"
                return
            }
            session = s
            if let p = peripheral { myPeripheralID = p.identifier }
            logEvent("会话建立成功（已记住本车外设 ID）")
            connected = true
            phase = .ready
            detail = "会话已建立"
            startPump()

            // 关键顺序：先加密握手，再执行排队动作（官方 CLI 也是 Connect→StartSession→发命令）
            let act = pendingAction
            pendingAction = nil
            Task {
                let ok = await Task.detached(priority: .userInitiated) { s.connect() }.value
                logEvent(ok ? "会话握手完成" : "会话握手失败：\(s.lastError())")
                if let act {
                    logEvent("执行动作")
                    act()
                }
                scheduleIdleDisconnect()
            }
        }
    }

    /// 上行：把协议栈要发的消息加长度前缀、按 MTU 分块写出去
    func write(_ message: Data) {
        guard let p = peripheral, let tx = txChar else { return }
        var out = Data()
        let len = UInt16(clamping: message.count)
        out.append(UInt8(len >> 8)); out.append(UInt8(len & 0xff))
        out.append(message)

        let maxLen = p.maximumWriteValueLength(for: .withoutResponse)
        let chunk = max(1, min(maxLen, 182))
        var offset = 0
        while offset < out.count {
            let end = min(offset + chunk, out.count)
            p.writeValue(out.subdata(in: offset..<end), for: tx, type: .withoutResponse)
            offset = end
        }
    }

    /// 下行：累积字节，凑齐一条完整消息后交给协议栈
    func ingest(_ data: Data) {
        rxBuffer.append(data)
        while rxBuffer.count >= 2 {
            let len = (Int(rxBuffer[rxBuffer.startIndex]) << 8)
                | Int(rxBuffer[rxBuffer.startIndex + 1])
            guard rxBuffer.count >= 2 + len else { break }
            let payload = rxBuffer.subdata(in: 2..<(2 + len))
            rxBuffer.removeSubrange(0..<(2 + len))
            session?.enqueue(payload)
        }
    }

    /// 持续把协议栈的发送队列刷到蓝牙
    func startPump() {
        pumpTask?.cancel()
        pumpTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let data = self.session?.waitDequeue(50), !data.isEmpty {
                    self.write(data)
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }
}

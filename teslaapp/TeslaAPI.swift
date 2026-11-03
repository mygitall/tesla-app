import Foundation
import Security

/// 轻量 Keychain 封装：用于存访问密钥（比 UserDefaults 安全）
enum KeychainStore {
    private static let service = "com.zhangweiwei.teslaapp"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func set(_ value: String, for key: String) {
        let q = baseQuery(key)
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var q = baseQuery(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
import Combine

// MARK: - 数据模型

struct TodayStats: Codable {
    var distanceKm: Double?
    var driveMinutes: Int?
    var energyKwh: Double?
    var energyEstimated: Bool?    // 能耗是否为估算值
    var cost: Double?
    var trips: Int?
    var gapKm: Double?            // 里程表比行程记录多出来的公里数
}


// MARK: - 充电统计

struct ChargeMonth: Codable, Identifiable {
    var key: String
    var year: Int
    var month: Int
    var count: Int
    var kwh: Double
    var minutes: Int
    var peak: Double
    var id: String { key }
}

struct ChargeSessionItem: Codable, Identifiable {
    var startTs: Int
    var endTs: Int
    var energyKwh: Double
    var peakPower: Double
    var startBattery: Int?
    var endBattery: Int?
    var durationMin: Int
    var samples: Int?
    var estimated: Bool?
    var durationEstimated: Bool?
    var truncated: Bool?
    var id: Int { startTs }
}

struct ChargeTotals: Codable {
    var count: Int
    var energyKwh: Double
    var minutes: Int
    var peakPower: Double
    var avgKwh: Double
    var minutesEstimated: Bool?
    var assumedKw: Double?
}

struct ChargeBaseline: Codable {
    var sessions: Int
    var kwh: Double
    var durationMin: Int?
    var assumedKw: Double?
    var updatedAt: String?
}

struct ChargeSummaryResp: Codable {
    var year: Int
    var month: Int?
    var allTime: Bool?
    var baseline: ChargeBaseline?
    var totals: ChargeTotals
    var sessions: [ChargeSessionItem]
}

struct ChargeCurvePoint: Codable, Identifiable {
    var ts: Int
    var battery: Int?
    var power: Double
    var voltage: Double?
    var current: Double?
    var id: Int { ts }
}

struct ChargeCurveResp: Codable {
    var points: [ChargeCurvePoint]
    var peakPower: Double?
    var count: Int?
}

struct ActionRecord: Codable, Identifiable {
    var id: Int
    var ts: Int
    var action: String
    var label: String?
    var ok: Bool
    var detail: String?
    var source: String?
}

struct ActionsResp: Codable {
    var ok: Bool?
    var actions: [ActionRecord]
    var hasMore: Bool?
}

struct BatteryHealth: Codable {
    var ok: Bool?
    var nominalRangeKm: Double?
    var fullRangeKm: Double?
    var healthPct: Double?
    var history: [BatteryHealthPoint]?
}

struct BatteryHealthPoint: Codable {
    var day: String?
    var ts: Int?
    var battery: Int?
    var rangeKm: Double?
}

struct ChargeMonthsResp: Codable {
    var months: [ChargeMonth]
    var totalSessions: Int
}


// MARK: - 行程

struct Trip: Codable, Identifiable {
    var id: Int
    var startTs: Int
    var endTs: Int
    var distanceKm: Double
    var durationMin: Int
    var startBattery: Int?
    var endBattery: Int?
    var maxSpeedKmh: Int?
    var avgSpeedKmh: Int?
    var startLat: Double?
    var startLon: Double?
    var endLat: Double?
    var endLon: Double?
    var samples: Int?
}

struct TripsTotals: Codable {
    var count: Int
    var distanceKm: Double
    var durationMin: Int
    var firstTs: Int?
    var lastTs: Int?
}

struct TripsResp: Codable {
    var trips: [Trip]
    var totals: TripsTotals?
}

struct TrackPoint: Codable, Identifiable {
    var ts: Int
    var lat: Double
    var lon: Double
    var frame: String?      // "gcj" = 已是国内坐标系，无需转换
    var speed: Int?
    var battery: Int?
    var id: Int { ts }
}

struct TripDetailResp: Codable { var track: [TrackPoint] }

struct VehicleSummary: Codable {
    var id: Int64
    var electricityPrice: Double?
    var name: String?
    var vin: String?
    var state: String

    var commandsEnabled: Bool?
    var autoLock: Bool?
    var autoLockDelaySec: Int?
    var ts: Int?

    var battery: Int?
    var batteryNominal: Int?
    var rangeKm: Int?
    var addedKm: Int?          // 上次充电增加的续航（km）
    var charging: String?
    var chargeLimit: Int?
    var locked: Bool?
    var userPresent: Bool?
    var odometerKm: Int?
    var insideTemp: Double?
    var outsideTemp: Double?
    var climateOn: Bool?
    var setTemp: Double?
    var lat: Double?
    var lon: Double?
    var speed: Double?
    var shift: String?
    var dataError: String?

    // 充电明细
    var chargerPower: Double?
    var chargerVoltage: Double?
    var chargerCurrent: Double?
    var chargeRate: Int?
    var energyAddedKwh: Double?
    var minutesToFull: Int?
    var chargePortOpen: Bool?
    var fastCharger: Bool?

    // 剩余电量（kWh）
    var batteryKwh: Double?
    var batteryCapacityKwh: Double?

    // 今日统计
    var today: TodayStats?

    var isOnline: Bool { state == "online" }
    var stateText: String {
        switch state {
        case "online": return "在线"
        case "asleep": return "休眠"
        case "offline": return "离线"
        default: return state
        }
    }
    var chargingText: String {
        switch charging {
        case "Charging": return "充电中"
        case "Complete": return "已充满"
        case "Stopped": return "已停止"
        case "Disconnected", nil: return "未连接"
        default: return charging ?? "未连接"
        }
    }
}

/// 采集器里的自动锁状态
struct RecorderAutoLock: Codable {
    var enabled: Bool?
    var delaySec: Int?
    var armed: Bool?
    var suppressFor: Int?
    var lastResult: String?
    var lastFireAt: Int?
    var lastError: String?
}

private struct RecorderStatus: Codable {
    var autoLock: RecorderAutoLock?
}

struct CommandResult: Codable {
    var ok: Bool?
    var message: String?
    var needPairing: Bool?
}

enum APIError: LocalizedError {
    case unauthorized
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "需要重新登录"
        case .message(let m): return m
        }
    }
}

// MARK: - 客户端

@MainActor
final class TeslaAPI: ObservableObject {
    static let shared = TeslaAPI()

    @Published var loggedIn = !AppConfig.accessKey.isEmpty
    /// 启动时若本地有缓存和密钥，立刻乐观进入首页（不等网络）
    private static let summaryCacheKey = "lastSummary.v1"

    private func loadSummaryCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.summaryCacheKey) else { return }
        if let s = try? JSONDecoder().decode(VehicleSummary.self, from: data) {
            summary = s
        }
    }

    private func saveSummaryCache(_ s: VehicleSummary) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.summaryCacheKey)
        }

    }

    static func cachedSummary() -> VehicleSummary? {
        guard let data = UserDefaults.standard.data(forKey: summaryCacheKey) else { return nil }
        return try? JSONDecoder().decode(VehicleSummary.self, from: data)
    }

    @Published var summary: VehicleSummary? = TeslaAPI.cachedSummary()
    @Published var loading = false
    /// 最后一次成功刷新的本地时间
    @Published var lastRefreshAt: Date?
    @Published var errorText: String?
    /// 各页面加载失败提示（加载成功会清空）
    @Published var chargeError: String?
    @Published var healthError: String?
    @Published var tripsError: String?
    /// 行程列表是否还有下一页
    @Published var tripsHasMore = false
    /// 电价（元/度），来自服务器设置
    @Published var electricityPrice: Double?
    /// 操作历史
    @Published var actions: [ActionRecord] = []
    @Published var actionsError: String?
    @Published var actionsLoading = false
    @Published var actionsHasMore = false
    /// 刷新连续失败次数（用于退避）
    @Published var consecutiveRefreshFailures = 0
    /// 首次加载是否已完成（用于首屏骨架屏）
    @Published var initialLoadDone = false
    /// 骨架屏最短展示时长（秒）
    var skeletonMinimum: Double = 0.7
    static let launchTime = Date()
    /// 最近一次失败的控制指令（用于「重试」按钮）
    @Published var lastFailedCommand: (action: String, label: String, body: [String: Any]?)?
    @Published var actionText: String?
    @Published var chargeMonths: [ChargeMonth] = []
    @Published var chargeSummary: ChargeSummaryResp?
    @Published var chargeLoading = false
    @Published var trips: [Trip] = []
    @Published var tripsTotals: TripsTotals?
    @Published var chargeCurvePeak: Double = 0
    @Published var tripsLoading = false
    @Published var actionIsError = false
    @Published var busy = false
    /// busy 开始时间，用于自动解除卡死
    private var busySince: Date?
    /// 明确被服务器拒绝（401/403）时才为 true；网络错误保持 false
    var lastAuthFailed = false

    /// 离车自动上锁是否开启（跟随服务器）
    var autoLockEnabled: Bool { summary?.autoLock ?? false }
    @Published var recorder: RecorderAutoLock?

    private let defaultBase = "https://www.zhangweiwei.cc"

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = HTTPCookieStorage.shared
        c.httpShouldSetCookies = true
        c.timeoutIntervalForRequest = 50
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    var baseURLString: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? AppConfig.serverURL }
        set {
            let old = UserDefaults.standard.string(forKey: "serverURL")
            UserDefaults.standard.set(newValue, forKey: "serverURL")
            // 换了服务器：清掉旧服务器的会话与缓存，避免串数据
            if old != newValue {
                clearAllCaches()
                loggedIn = false
            }
        }
    }

    /// 免密密钥（/k/<key>），存在本地；首次运行自动写入内置密钥
    var accessKey: String {
        get {
            // 1) 优先读 Keychain
            if let v = KeychainStore.get("accessKey"), !v.isEmpty { return v }
            // 2) 迁移：老版本存在 UserDefaults 的明文密钥
            let legacy = UserDefaults.standard.string(forKey: "accessKey") ?? ""
            if !legacy.isEmpty {
                KeychainStore.set(legacy, for: "accessKey")
                UserDefaults.standard.removeObject(forKey: "accessKey")
                return legacy
            }
            // 3) 内置密钥：永远自动使用（打开 App 直接进主页面，无感登录）
            if !AppConfig.accessKey.isEmpty {
                KeychainStore.set(AppConfig.accessKey, for: "accessKey")
                return AppConfig.accessKey
            }
            return ""
        }
        set {
            if newValue.isEmpty {
                KeychainStore.delete("accessKey")
            } else {
                KeychainStore.set(newValue, for: "accessKey")
                UserDefaults.standard.set(false, forKey: "didExplicitLogout")
            }
        }
    }

    /// 从「纯密钥」或「完整链接」里解析出密钥
    static func parseKey(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if let r = t.range(of: "/k/") {
            let rest = String(t[r.upperBound...])
            return rest.components(separatedBy: CharacterSet(charactersIn: "?&#/ ")).first ?? ""
        }
        if let comps = URLComponents(string: t),
           let k = comps.queryItems?.first(where: { $0.name == "k" })?.value {
            return k
        }
        return t
    }

    private var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: defaultBase)!
    }

    private func url(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL) ?? baseURL
    }

    // MARK: - 离线缓存（断网时仍能看历史）

    private func cacheURL(_ key: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("cache-\(key).json")
    }

    private func saveDiskCache(_ key: String, _ data: Data) {
        guard let u = cacheURL(key) else { return }
        try? data.write(to: u, options: [.atomic, .completeFileProtection])
    }

    private func loadDiskCache(_ key: String) -> Data? {
        guard let u = cacheURL(key), let d = try? Data(contentsOf: u) else { return nil }
        return d
    }

    /// 缓存有多旧（用于提示"离线·3 小时前"）
    func cacheAge(_ key: String) -> String? {
        guard let u = cacheURL(key),
              let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        let mins = Int(Date().timeIntervalSince(date) / 60)
        if mins < 2 { return "刚刚" }
        if mins < 60 { return "\(mins) 分钟前" }
        if mins < 1440 { return "\(mins / 60) 小时前" }
        return "\(mins / 1440) 天前"
    }

    /// 把任意错误翻成给用户看的一句话
    private func friendly(_ error: Error) -> String {
        if let e = error as? APIError {
            switch e {
            case .unauthorized: return "登录已过期，请重新登录"
            case .message(let m): return m
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "没有网络连接"
            case NSURLErrorTimedOut: return "请求超时（服务器或车辆响应慢）"
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost: return "连不上服务器"
            default: break
            }
        }
        return error.localizedDescription
    }

    /// 统一的 JSON 请求：非 200 也当作错误抛出（之前直接 return，用户什么都看不到）
    private func fetch<T: Decodable>(_ path: String, timeout: TimeInterval = 25, cacheKey: String? = nil) async throws -> T {
        var req = URLRequest(url: url(path))
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.message("网络异常") }
        if http.statusCode == 401 { loggedIn = false; throw APIError.unauthorized }
        guard http.statusCode == 200 else {
            throw APIError.message("服务器返回 \(http.statusCode)")
        }
        if let key = cacheKey { saveDiskCache(key, data) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func hasSessionCookie() -> Bool {
        let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        return cookies.contains { $0.name == "dash_sess" }
    }

    // MARK: 启动恢复

    func restore() async {
        // 有密钥就立刻放行进首页，网络校验放后台做（避免启动转圈）
        loadSummaryCache()
        if !accessKey.isEmpty { loggedIn = true }

        if !hasSessionCookie(), !accessKey.isEmpty {
            _ = try? await keyLogin(accessKey)
        }
        // 没网时不强求校验成功：只要本地有会话 cookie 就当已登录，
        // 这样飞行模式下仍能使用蓝牙开关车门
        let hasCookie = hasSessionCookie()
        if !hasCookie {
            loggedIn = false
            return
        }

        let ok = await verifySession()
        if !ok {
            // 网络问题 → 仍进入主界面（界面数据会提示离线）
            // 只有明确拿到 401 才登出
            if lastAuthFailed {
                loggedIn = false
                return
            }
        }
        loggedIn = true
        await refresh()   // 后台刷新，不阻塞界面
        return
        if await verifySession() {
            loggedIn = true
            await refresh()
        } else {
            loggedIn = false
        }
    }

    func verifySession() async -> Bool {
        var req = URLRequest(url: url("/api/status"))
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        do {
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            if http.statusCode == 401 || http.statusCode == 403 {
                lastAuthFailed = true       // 真的没权限
                return false
            }
            lastAuthFailed = false
            return http.statusCode == 200
        } catch {
            // 网络不通（飞行模式/没信号）：不算认证失败，保持登录态
            lastAuthFailed = false
            return false
        }
    }

    // MARK: 登录

    func login(password: String) async throws {
        var req = URLRequest(url: url("/login"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let enc = password.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        req.httpBody = Data("password=\(enc)".utf8)

        let (_, resp): (Data, URLResponse)
        do {
            (_, resp) = try await session.data(for: req)
        } catch {
            throw APIError.message("连不上服务器，请检查网络或地址")
        }

        guard let http = resp as? HTTPURLResponse else {
            throw APIError.message("网络异常")
        }
        switch http.statusCode {
        case 200, 302:
            break
        case 401:
            throw APIError.message("密码错误")
        case 429:
            throw APIError.message("尝试过于频繁，请几分钟后再试")
        default:
            throw APIError.message("登录失败（HTTP \(http.statusCode)）")
        }

        // 302 会被自动跟随，最终可能拿到 200；以 cookie / 会话校验为准
        if !hasSessionCookie() {
            let ok = await verifySession()
            if !ok {
                throw APIError.message("登录未成功，请检查服务器地址")
            }
        }

        loggedIn = true
        await refresh()   // 后台刷新，不阻塞界面
    }

    /// 用密钥换登录会话：GET /k/<key> 服务端会回 302 + Set-Cookie
    @discardableResult
    func keyLogin(_ raw: String) async throws -> Bool {
        let key = Self.parseKey(raw)
        guard key.count >= 16 else { throw APIError.message("密钥格式不对") }

        var req = URLRequest(url: url("/k/\(key)"))
        req.httpMethod = "GET"
        req.timeoutInterval = 30

        do {
            _ = try await session.data(for: req)
        } catch {
            throw APIError.message("连不上服务器，请检查网络")
        }

        guard hasSessionCookie(), await verifySession() else {
            throw APIError.message("密钥无效或已失效")
        }
        accessKey = key
        loggedIn = true
        await refresh()   // 后台刷新，不阻塞界面
        return true
    }

    /// 兼容旧调用：清本地数据但保持登录态（不会把用户踢到登录页）
    /// 清理本地数据并立即用内置密钥重新登录（不打断使用，永远不进登录页）
    func resetLocalData() async {
        accessKey = AppConfig.accessKey
        clearAllCaches()
        summary = nil
        lastRefreshAt = nil
        actions = []
        lastFailedCommand = nil
        actionText = "本地数据已清除"
        loggedIn = !accessKey.isEmpty
        await refresh()
    }

    /// 兼容旧调用：等同 resetLocalData，不再把用户踢到登录页
    func logout() {
        accessKey = AppConfig.accessKey
        clearAllCaches()
        summary = nil
        lastRefreshAt = nil
        actions = []
        lastFailedCommand = nil
        loggedIn = !accessKey.isEmpty
        actionText = nil
    }

    /// 清掉本地所有数据（换账号/退出/换服务器时调用）
    func clearAllCaches() {
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        URLCache.shared.removeAllCachedResponses()
        if let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasPrefix("cache-") {
                try? FileManager.default.removeItem(at: f)
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.summaryCacheKey)   // 车况缓存
        CrashLogger.clear()
        summary = nil
        lastRefreshAt = nil
        chargeSummary = nil
        trips = []
        tripsTotals = nil
        batteryHealth = nil
    }

    // MARK: 刷新

    func refresh() async {
        guard !loading else { return }
        loading = true
        errorText = nil
        defer { loading = false }

        do {
            let s: VehicleSummary = try await get("/api/app/summary", timeout: 55)
            summary = s
            lastRefreshAt = Date()
            consecutiveRefreshFailures = 0
            if let p = s.electricityPrice { electricityPrice = p }
            saveSummaryCache(s)
            if s.dataError != nil {
                errorText = "车辆数据读取失败，稍后再试"
            }
            if let r: RecorderStatus = try? await get("/api/recorder", timeout: 20) {
                recorder = r.autoLock
            }
        } catch APIError.unauthorized {
            loggedIn = false
            consecutiveRefreshFailures += 1
        } catch {
            errorText = friendly(error)
            consecutiveRefreshFailures += 1
        }
        // 骨架屏至少显示 0.7 秒：否则网络快时会一闪而过，微光根本看不到
        let elapsed = Date().timeIntervalSince(Self.launchTime)
        if skeletonMinimum > 0, elapsed < skeletonMinimum {
            try? await Task.sleep(nanoseconds: UInt64((skeletonMinimum - elapsed) * 1_000_000_000))
        }
        initialLoadDone = true
    }

    private func get<T: Decodable>(_ path: String, timeout: TimeInterval = 25) async throws -> T {
        var req = URLRequest(url: url(path))
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.message("网络异常") }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard http.statusCode < 400 else {
            throw APIError.message("服务器返回 \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: 指令

    func command(_ action: String, label: String, body: [String: Any]? = nil) async {
        // 卡死自愈：超过 25 秒仍 busy，视为异常并允许重试
        if busy, let t = busySince, Date().timeIntervalSince(t) > 25 {
            busy = false
            busySince = nil
        }
        guard !busy else { return }
        busy = true
        busySince = Date()
        actionIsError = false
        actionText = "\(label)中…"
        defer { busy = false; busySince = nil }

        var req = URLRequest(url: url("/api/cmd/\(action)"))
        req.httpMethod = "POST"
        req.timeoutInterval = 130          // 车在睡时要先唤醒，可能等 30~60 秒
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body, let data = try? JSONSerialization.data(withJSONObject: body) {
            req.httpBody = data
        } else {
            req.httpBody = Data("{}".utf8)
        }

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                actionText = "✗ 网络异常"; actionIsError = true
            lastFailedCommand = (action, label, body)
            return
            }
            if http.statusCode == 401 {
                loggedIn = false
                return
            }
            let r = try? JSONDecoder().decode(CommandResult.self, from: data)
            if http.statusCode == 200, r?.ok == true {
                actionText = "✓ \(label)成功"
                actionIsError = false
                await refresh()
            } else {
                var msg = r?.message ?? "执行失败"
                if r?.needPairing == true { msg = "车辆还没配对密钥" }
                if msg.count > 60 { msg = String(msg.prefix(60)) + "…" }
                actionText = "✗ \(msg)"
                actionIsError = true
                lastFailedCommand = (action, label, body)
            }
        } catch {
            actionText = "✗ \(error.localizedDescription)"
            actionIsError = true
            lastFailedCommand = (action, label, body)
        }
    }

    /// 设定空调温度（15~28°C）
    func setTemperature(_ celsius: Double) async {
        let t = min(28, max(15, celsius))
        await command("set-temp", label: "温度 \(Int(t))°", body: ["temp": t])
    }

    /// 重试最近一次失败的控制指令
    func retryLastCommand() async {
        guard let c = lastFailedCommand else { return }
        lastFailedCommand = nil
        await command(c.action, label: c.label, body: c.body)
    }

    // MARK: 设置

    /// 行程列表
    /// 分页：append = true 时按已有数量继续取下一页
    func loadTrips(append: Bool = false) async {
        guard !tripsLoading else { return }
        tripsLoading = true
        defer { tripsLoading = false }
        let offset = append ? trips.count : 0
        do {
            let r: TripsResp = try await fetch("/api/trips?limit=50&offset=\(offset)", cacheKey: offset == 0 ? "trips" : nil)
            if append {
                // 去重（避免服务器有新行程导致 offset 漂移）
                let known = Set(trips.map { $0.id })
                trips += r.trips.filter { !known.contains($0.id) }
            } else {
                trips = r.trips
            }
            tripsTotals = r.totals
            tripsHasMore = r.trips.count >= 50
            tripsError = nil
        } catch {
            if !append, let d = loadDiskCache("trips"),
               let r = try? JSONDecoder().decode(TripsResp.self, from: d) {
                trips = r.trips
                tripsTotals = r.totals
                tripsError = "离线 · 显示 \(cacheAge("trips") ?? "缓存")的行程"
            } else {
                tripsError = friendly(error)
            }
        }
    }

    /// 单段行程的轨迹点
    func loadTripTrack(id: Int) async -> [TrackPoint] {
        var req = URLRequest(url: url("/api/trips/\(id)"))
        req.httpMethod = "GET"
        req.timeoutInterval = 25
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return try JSONDecoder().decode(TripDetailResp.self, from: data).track
        } catch {
            return []
        }
    }

    /// 告诉服务器「手机就在车边」：抑制离车自动锁 + 保持高频采集
    func presence(seconds: Int = 180, present: Bool = true) async {
        var req = URLRequest(url: url("/api/recorder/presence?sec=\(seconds)&present=\(present ? 1 : 0)"))
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        _ = try? await session.data(for: req)
    }

    /// 通知服务器进入高频采集（App 蓝牙连上车辆时调用），避免漏记短途
    func wakeRecorder(seconds: Int = 900) async {
        var req = URLRequest(url: url("/api/recorder/wake?sec=\(seconds)"))
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        _ = try? await session.data(for: req)
    }

    /// 充电曲线（不传时间则取最近一次充电）
    func loadChargeCurve(start: Int? = nil, end: Int? = nil) async -> [ChargeCurvePoint] {
        var path = "/api/charge/curve"
        if let start, let end { path += "?start=\(start)&end=\(end)" }
        do {
            let r: ChargeCurveResp = try await fetch(path)
            chargeCurvePeak = r.peakPower ?? 0
            return r.points
        } catch {
            chargeError = friendly(error)
            return []
        }
    }

    // MARK: 电池健康度

    @Published var batteryHealth: BatteryHealth?

    func loadBatteryHealth() async {
        do {
            batteryHealth = try await fetch("/api/charge/health")
            healthError = nil
        } catch {
            healthError = friendly(error)
        }
    }

    /// 充电月份列表
    func loadChargeMonths() async {
        var req = URLRequest(url: url("/api/charge/months"))
        req.httpMethod = "GET"
        req.timeoutInterval = 25
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            let r = try JSONDecoder().decode(ChargeMonthsResp.self, from: data)
            chargeMonths = r.months
        } catch {
            actionText = "充电月份加载失败：\(error.localizedDescription)"
        }
    }

    /// 全部时间（含官方历史基线）
    func loadChargeSummaryAll() async {
        chargeLoading = true
        defer { chargeLoading = false }
        do {
            chargeSummary = try await fetch("/api/charge/summary?range=all", timeout: 40, cacheKey: "charge-summary-all")
            chargeError = nil
        } catch {
            if let d = loadDiskCache("charge-summary-all"),
               let sum = try? JSONDecoder().decode(ChargeSummaryResp.self, from: d) {
                chargeSummary = sum
                chargeError = "离线 · 显示 \(cacheAge("charge-summary-all") ?? "缓存")的数据"
            } else {
                chargeError = friendly(error)
            }
        }
    }

    /// 保存官方 App 的历史基线
    func saveChargeBaseline(sessions: Int, kwh: Double, durationMin: Int = 0, assumedKw: Double = 60) async {
        var req = URLRequest(url: url("/api/charge/baseline"))
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{\"sessions\":\(sessions),\"kwh\":\(kwh),\"durationMin\":\(durationMin),\"assumedKw\":\(assumedKw)}".utf8)
        do {
            _ = try await session.data(for: req)
            actionText = "历史基线已保存：\(sessions) 次 / \(String(format: "%.0f", kwh)) 度"
        } catch {
            actionText = "基线保存失败：\(error.localizedDescription)"
        }
    }

    /// 某年某月的充电汇总（month 传 nil 表示整年）
    func loadChargeSummary(year: Int, month: Int?) async {
        chargeLoading = true
        defer { chargeLoading = false }
        var path = "/api/charge/summary?year=\(year)"
        if let month { path += "&month=\(month)" }
        do {
            let key = "charge-summary-\(year)-\(month ?? 0)"
            chargeSummary = try await fetch(path, cacheKey: key)
            chargeError = nil
        } catch {
            let key = "charge-summary-\(year)-\(month ?? 0)"
            if let d = loadDiskCache(key),
               let sum = try? JSONDecoder().decode(ChargeSummaryResp.self, from: d) {
                chargeSummary = sum
                chargeError = "离线 · 显示 \(cacheAge(key) ?? "缓存")的数据"
            } else {
                chargeError = friendly(error)
            }
        }
    }

    /// 操作历史（谁在何时锁车/开空调）
    func loadActions(append: Bool = false) async {
        guard !actionsLoading else { return }
        actionsLoading = true
        defer { actionsLoading = false }
        let offset = append ? actions.count : 0
        do {
            let r: ActionsResp = try await fetch("/api/actions?limit=50&offset=\(offset)", cacheKey: offset == 0 ? "actions" : nil)
            if append {
                let known = Set(actions.map { $0.id })
                actions += r.actions.filter { !known.contains($0.id) }
            } else {
                actions = r.actions
            }
            actionsHasMore = r.hasMore ?? (r.actions.count >= 50)
            actionsError = nil
        } catch {
            if !append, let d = loadDiskCache("actions"),
               let r = try? JSONDecoder().decode(ActionsResp.self, from: d) {
                actions = r.actions
                actionsError = "离线 · 显示 \(cacheAge("actions") ?? "缓存")的记录"
            } else {
                actionsError = friendly(error)
            }
        }
    }

    /// 修改电价（元/度）
    func setElectricityPrice(_ price: Double) async {
        var req = URLRequest(url: url("/api/settings"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{\"electricityPrice\":\(price)}".utf8)
        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 { loggedIn = false }
            await refresh()
        } catch {
            errorText = "电价保存失败：\(friendly(error))"
        }
    }

    func setAutoLock(_ on: Bool) async {
        var req = URLRequest(url: url("/api/settings"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{\"autoLock\":\(on)}".utf8)
        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
                loggedIn = false
            }
            await refresh()
        } catch {
            errorText = "设置失败：\(error.localizedDescription)"
        }
    }
}

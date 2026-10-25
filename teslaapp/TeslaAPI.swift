import Foundation
import Combine

// MARK: - 数据模型

struct TodayStats: Codable {
    var distanceKm: Double?
    var driveMinutes: Int?
    var energyKwh: Double?
    var cost: Double?
    var trips: Int?
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
        set { UserDefaults.standard.set(newValue, forKey: "serverURL") }
    }

    /// 免密密钥（/k/<key>），存在本地；首次运行自动写入内置密钥
    var accessKey: String {
        get {
            let v = UserDefaults.standard.string(forKey: "accessKey") ?? ""
            if v.isEmpty {
                UserDefaults.standard.set(AppConfig.accessKey, forKey: "accessKey")
                return AppConfig.accessKey
            }
            return v
        }
        set { UserDefaults.standard.set(newValue, forKey: "accessKey") }
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

    func logout() {
        HTTPCookieStorage.shared.cookies(for: baseURL)?.forEach {
            HTTPCookieStorage.shared.deleteCookie($0)
        }
        // 保留内置密钥，退出后仍可自动登录
        loggedIn = false
        summary = nil
        actionText = nil
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
            saveSummaryCache(s)
            if s.dataError != nil {
                errorText = "车辆数据读取失败，稍后再试"
            }
            if let r: RecorderStatus = try? await get("/api/recorder", timeout: 20) {
                recorder = r.autoLock
            }
        } catch APIError.unauthorized {
            loggedIn = false
        } catch {
            errorText = error.localizedDescription
        }
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

    func command(_ action: String, label: String) async {
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
        req.httpBody = Data("{}".utf8)

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                actionText = "✗ 网络异常"; actionIsError = true; return
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
            }
        } catch {
            actionText = "✗ \(error.localizedDescription)"
            actionIsError = true
        }
    }

    // MARK: 设置

    /// 行程列表
    func loadTrips() async {
        tripsLoading = true
        defer { tripsLoading = false }
        var req = URLRequest(url: url("/api/trips?limit=50"))
        req.httpMethod = "GET"
        req.timeoutInterval = 25
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            let r = try JSONDecoder().decode(TripsResp.self, from: data)
            trips = r.trips
            tripsTotals = r.totals
        } catch {
            actionText = "行程加载失败：\(error.localizedDescription)"
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
        var req = URLRequest(url: url(path))
        req.httpMethod = "GET"
        req.timeoutInterval = 25
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let r = try JSONDecoder().decode(ChargeCurveResp.self, from: data)
            chargeCurvePeak = r.peakPower ?? 0
            return r.points
        } catch { return [] }
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
        var req = URLRequest(url: url("/api/charge/summary?range=all"))
        req.httpMethod = "GET"
        req.timeoutInterval = 25
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            chargeSummary = try JSONDecoder().decode(ChargeSummaryResp.self, from: data)
        } catch {
            actionText = "充电统计加载失败：\(error.localizedDescription)"
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
        var req = URLRequest(url: url(path))
        req.httpMethod = "GET"
        req.timeoutInterval = 25
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            chargeSummary = try JSONDecoder().decode(ChargeSummaryResp.self, from: data)
        } catch {
            actionText = "充电统计加载失败：\(error.localizedDescription)"
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

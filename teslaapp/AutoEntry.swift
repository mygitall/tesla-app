import Foundation
import CoreLocation

/// 地理围栏自动解锁：进入车周围区域时唤醒 App 连一次蓝牙，
/// 用信号强度确认真的在车旁，然后解锁。平时完全不碰车。
@MainActor
final class AutoEntry: NSObject, ObservableObject {

    @Published var enabled = false
    @Published var status = "未启用"
    @Published var enterCount = 0
    /// 围栏半径（米）：越小越省手机电，但太小时定位抖动可能漏触发
    var radiusMeters: Double = 80

    /// 进入区域（由 HomeView 接上 BLE 动作）
    var onEnter: (() -> Void)?
    /// 离开区域
    var onExit: (() -> Void)?

    private let lm = CLLocationManager()
    private var region: CLCircularRegion?
    private var coord: CLLocationCoordinate2D?

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 设置车辆位置（来自服务器最后已知坐标）
    func configure(lat: Double?, lon: Double?) {
        guard let lat, let lon, lat != 0, lon != 0 else { return }
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        if let old = coord, abs(old.latitude - lat) < 0.0002, abs(old.longitude - lon) < 0.0002 {
            return // 位置没变，不重建区域
        }
        coord = c
        if enabled { startMonitoring() }
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        if on {
            requestAuthorization()
        } else {
            stopMonitoring()
            status = "已关闭"
        }
    }

    private func requestAuthorization() {
        switch lm.authorizationStatus {
        case .notDetermined:
            lm.requestAlwaysAuthorization()
        case .authorizedAlways:
            startMonitoring()
        case .authorizedWhenInUse:
            status = "需要「始终允许」定位，请在设置里改"
            lm.requestAlwaysAuthorization()
        default:
            status = "定位权限被拒绝，请到设置里开启"
        }
    }

    private func startMonitoring() {
        guard let c = coord else { status = "还不知道车停哪"; return }
        stopMonitoring()
        let r = CLCircularRegion(center: c, radius: radiusMeters, identifier: "tesla-car")
        r.notifyOnEntry = true
        r.notifyOnExit = true
        region = r
        lm.startMonitoring(for: r)
        status = "已开启 · 进入 \(Int(radiusMeters)) 米内尝试解锁"
    }

    private func stopMonitoring() {
        if let r = region { lm.stopMonitoring(for: r) }
        region = nil
    }
}

extension AutoEntry: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        Task { @MainActor in
            switch st {
            case .authorizedAlways:
                self.startMonitoring()
            case .authorizedWhenInUse:
                self.status = "只给了「使用期间」权限，自动解锁需要「始终」"
            case .denied:
                self.status = "定位权限被拒绝"
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            self.status = "已到车附近，正在连接…"
            self.enterCount += 1
            self.onEnter?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            self.status = "已离开车辆范围"
            self.onExit?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in self.status = "定位错误：\(msg)" }
    }
}

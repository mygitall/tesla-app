import Foundation
import CoreLocation

/// 把行程坐标反查成城市名（本地缓存，避免重复调用系统地理编码）
final class CityIndex {
    static let shared = CityIndex()

    private let cacheKey = "city.cache.v1"
    private var cache: [String: String]
    private var busy = false

    private init() {
        cache = (UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String]) ?? [:]
    }

    /// 坐标 → 缓存 key（约 5km 粒度，避免同一城市多次请求）
    private func key(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.2f,%.2f", (lat * 20).rounded() / 20, (lon * 20).rounded() / 20)
    }

    func cachedCity(lat: Double, lon: Double) -> String? {
        cache[key(lat, lon)]
    }

    /// 批量解析：返回 [城市: 次数]，只取前 limit 个不同坐标
    func cities(from trips: [Trip], limit: Int = 8, completion: @escaping ([String: Int]) -> Void) {
        // 收集坐标（起点+终点），按缓存 key 去重
        var points: [(lat: Double, lon: Double)] = []
        var seen = Set<String>()
        for t in trips {
            for (la, lo) in [(t.startLat, t.startLon), (t.endLat, t.endLon)] {
                guard let la, let lo, abs(la) > 0.001, abs(lo) > 0.001 else { continue }
                let k = key(la, lo)
                if seen.contains(k) { continue }
                if cache[k] != nil { continue }
                seen.insert(k)
                points.append((la, lo))
            }
        }

        // 先算已缓存的
        var result: [String: Int] = [:]
        for t in trips {
            for (la, lo) in [(t.startLat, t.startLon), (t.endLat, t.endLon)] {
                guard let la, let lo, abs(la) > 0.001, abs(lo) > 0.001 else { continue }
                if let c = cache[key(la, lo)] { result[c, default: 0] += 1 }
            }
        }

        let need = Array(points.prefix(limit))
        guard !need.isEmpty, !busy else { completion(result); return }
        busy = true

        // 串行解析（系统地理编码有频率限制，约 1 次/秒）
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let geocoder = CLGeocoder()
            var idx = 0
            func step() {
                if idx >= need.count {
                    DispatchQueue.main.async {
                        self.busy = false
                        UserDefaults.standard.set(self.cache, forKey: self.cacheKey)
                        var final = result
                        for t in trips {
                            for (la, lo) in [(t.startLat, t.startLon), (t.endLat, t.endLon)] {
                                guard let la, let lo, abs(la) > 0.001, abs(lo) > 0.001 else { continue }
                                if let c = self.cache[self.key(la, lo)] { final[c, default: 0] += 1 }
                            }
                        }
                        completion(final)
                    }
                    return
                }
                let p = need[idx]
                idx += 1
                geocoder.reverseGeocodeLocation(
                    CLLocation(latitude: p.lat, longitude: p.lon),
                    preferredLocale: Locale(identifier: "zh_CN")
                ) { marks, _ in
                    if let m = marks?.first {
                        let city = m.locality ?? m.subAdministrativeArea ?? m.administrativeArea
                        if let city, !city.isEmpty {
                            DispatchQueue.main.async { self.cache[self.key(p.lat, p.lon)] = city }
                        }
                    }
                    // 节流，避免被限流
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { step() }
                }
            }
            step()
        }
    }
}
